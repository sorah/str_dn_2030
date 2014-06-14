require 'str_dn_2030/version'
require 'str_dn_2030/input'
require 'str_dn_2030/zone'
require 'socket'
require 'thread'

module StrDn2030
  class Remote
    VOLUME_STATUS_REGEXP = /\x02\x06\xA8\x92(?<zone>.)(?<type>.)(?<volume>..)./nm
    STATUS_REGEXP = /\x02\x07\xA8\x82(?<zone>.)(?<ch>.)(?<ch2>.)(?<flag1>.)(?<unused>.)./nm

    INPUT_REGEXP = /(?<index>.)(?<audio>.)(?<video>.)(?<icon>.)(?<preset_name>.{8})(?<name>.{8})(?<skip>.)/mn
    INPUTLIST_REGEXP = Regexp.new(
      '\x02\xD7\xA8\x8B(?<zone>.)' \
      "(?<inputs>(?:#{INPUT_REGEXP}){10})" \
      '\x00\x00.',
      Regexp::MULTILINE,
      'n'
    )
    def initialize(host, port = 33335)
      @host, @port = host, port

      @socket = nil
      @receiver_thread = nil

      @lock = Mutex.new
      @receiver_lock = Mutex.new
      @hook = nil

      @listeners = {}
      @listeners_lock = Mutex.new

      @inputs = {}
      @statuses = {}
    end

    attr_reader :inputs, :host, :port

    def inspect
      "#<#{self.class.name}: #{@host}:#{@port}>"
    end

    def hook(&block)
      if block_given?
        @hook = block
      else
        @hook
      end
    end

    def listen(type, filter = nil)
      Thread.current[:strdn2030_filter] = filter
      @listeners_lock.synchronize {
        @listeners[type] ||= []
        @listeners[type] << Thread.current
      }

      sleep

      data = Thread.current[:strdn2030_data]
      Thread.current[:strdn2030_data] = nil
      data
    end


    def connected?
      !!@socket
    end

    def connect
      disconnect if connected?

      @lock.synchronize do
        @socket = TCPSocket.open(@host, @port)
        start_receiver
        reload_input
        self
      end
    end

    def disconnect
      @lock.synchronize do
        return unless @socket
        @socket.close unless @socket.closed?
        @socket = nil
        stop_receiver
      end
    end

    def reload
      reload_input
      @statuses = {}
      self
    end

    def zone(zone_id)
      Zone.new(self, zone_id.is_a?(String) ? zone_id.ord : zone_id.to_i)
    end

    #### These are private api

    def status_get(zone_id = 0)
      @statuses[zone_id] || begin
        zone = zone_id.chr('ASCII-8BIT')
        send "\x02\x03\xA0\x82".b + zone + "\x00".b
        listen(:status, zone_id)
      end
    end

    def volume_get(zone_id, type = "\x03".b)
      zone = zone_id.chr('ASCII-8BIT')
      send "\x02\x04\xa0\x92".b + zone + type + "\x00".b
      listen(:volume, zone_id)
    end

    def volume_set(zone_id, other, type = "\x03".b)
      zone = zone_id.chr('ASCII-8BIT')
      send "\x02\x06\xa0\x52".b + zone + type + [other.to_i].pack('s>') + "\x00".b
      listen(:success)
      other
    end

    def active_input_get(zone_id)
      current = status_get(zone_id)[:ch][:video]
      inputs[zone_id][current] || self.reload_input.inputs[zone_id][current]
    end

    def active_input_set(zone_id, other)
      new_input = if other.is_a?(Input)
        raise ArgumentError, "#{other.inspect} is not in zone #{zone_id}" unless other.zone == zone_id
        other
      else
        inputs[zone_id][other] || self.reload_input.inputs[zone_id][other]
      end

      raise ArgumentError, "#{other.inspect} not exists" unless new_input
      
      zone = zone_id.chr('ASCII-8BIT')
      send "\x02\x04\xa0\x42".b + zone + new_input.video + "\x00".b
      listen(:success)
      other
    end

    def mute_set(zone_id, new_mute)
      zone = zone_id.chr('ASCII-8BIT')
      send "\x02\x04\xa0\x53".b + zone + (new_mute ? "\x01".b : "\x00".b) + "\x00".b
      listen(:success)
      new_mute
    end

    def reload_input
      @inputs = {}
      get_input_list(0, 0)
      listen(:input_list, 0)
      get_input_list(0, 1)
      listen(:input_list, 0)
      get_input_list(1, 0)
      listen(:input_list, 1)
      get_input_list(1, 1)
      listen(:input_list, 1)
      self
    end

    private

    def receiver_alive?
      @receiver_thread && @receiver_thread.alive?
    end

    def start_receiver(if_dead=false)
      return if if_dead && receiver_alive?
      stop_receiver
      @receiver_lock.synchronize do
        debug [:start_receiver]
        @receiver_thread = Thread.new(@socket, &method(:receiver))
        @receiver_thread.abort_on_exception = true
      end
    end

    def stop_receiver
      @receiver_lock.synchronize do
        debug [:stop_receiver]
        @receiver_thread.kill if receiver_alive?
        @receiver_thread = nil
      end
    end

    def get_input_list(zone_id, page = 0)
      send("\x02\x04\xa0\x8b".b + zone_id.chr('ASCII-8BIT') + page.chr('ASCII-8BIT') + "\x00".b)
    end

    def send(str)
      start_receiver(true)
      debug [:send, str]
      @socket.write str
    end

    def receiver(socket)
      buffer = "".b

      hit = false
      handle = lambda do |pattern, &handler|
        if m = buffer.match(pattern)
          hit = true
          buffer.replace(m.pre_match + m.post_match)
          handler[m]
        end
      end

      while chunk = socket.read(1)
        hit = false
        buffer << chunk.b

        handle.(STATUS_REGEXP, &method(:handle_status))
        handle.(VOLUME_STATUS_REGEXP, &method(:handle_volume_status))
        handle.(INPUTLIST_REGEXP, &method(:handle_input_list))

        handle.(/\A\xFD/n) { delegate(:success) }
        handle.(/\A\xFE/n) { delegate(:error) }

        debug([:buffer_remain, buffer]) if hit && !buffer.empty?
      end
    end

    def delegate(name, subtype = nil, *args)
      wake_listener name, subtype, *args
      @hook.call(name, *args) if @hook
    end

    def wake_listener(type, subtype, data = nil)
      @listeners_lock.synchronize do
        @listeners[type] ||= []
        @listeners[type].each do |th|
          next if th[:strdn2030_filter] && !(th[:strdn2030_filter] === subtype)
          th[:strdn2030_data] = data
          th.wakeup
        end
        @listeners[type].clear
      end
    end

    def handle_status(m)
      flag1 = m['flag1'].ord
      flags = {
        raw: [m['flag1']].map{ |_| _.ord.to_s(2).rjust(8,' ') },
        power: flag1[0] == 1,
        mute: flag1[1] == 1,
        headphone: flag1[2] == 1,
        unknown_6: flag1[5],
      }
      data = @statuses[m['zone'].ord] = {
        zone: m['zone'], ch: {audio: m['ch'], video: m['ch2']}, flags: flags
      }

      delegate(:status, m['zone'].ord, data)
    end

    def handle_volume_status(m)
      data = {zone: m['zone'], type: m['type'], volume: m['volume'].unpack('s>').first}
      delegate(:volume, m['zone'].ord, data)
    end

    def handle_input_list(m)
      #p m
      inputs = {}
      zone = m['zone'].ord
      m['inputs'].scan(INPUT_REGEXP).each do |input_line|
        idx, audio, video, icon, preset_name, name, skip_flags = input_line

        input = inputs[audio] = inputs[video] = Input.new(
          self,
          zone,
          idx,
          audio,
          video,
          icon,
          preset_name,
          name,
          skip_flags,
        )
        inputs[input.name] = input
      end
      (@inputs[zone] ||= {}).merge! inputs
      delegate :input_list, zone, inputs
    end

    def debug(*args)
      p(*args) if ENV["STR_DN_2030_DEBUG"]
    end
  end
end

