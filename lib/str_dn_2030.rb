require 'str_dn_2030/version'
require 'str_dn_2030/input'
require 'socket'
require 'thread'

module StrDn2030
  class ArefProxy
    def initialize(parent, name)
      @parent = parent
      @set = :"#{name}_set"
      @get = :"#{name}_get"
    end

    def [](*args)
      @parent.__send__ @get, *args
    end

    def []=(*args)
      @parent.__send__ @set, *args
    end
  end

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
      @hook = nil

      @listeners = {}
      @listeners_lock = Mutex.new

      @inputs = {}
      @statuses = {}

      @volumes_proxy = ArefProxy.new(self, 'volume')
      @active_inputs_proxy = ArefProxy.new(self, 'active_input')
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
        @receiver_thread = Thread.new(@socket, &method(:receiver))
        @receiver_thread.abort_on_exception = true
        reload_input
        self
      end
    end

    def disconnect
      @lock.synchronize do
        return unless @socket
        @socket.close unless @socket.closed?
        @receiver_thread.kill if @receiver_thread.alive?
        @socket = nil
        @receiver_thread = nil
      end
    end

    def reload
      reload_input
      @statuses = {}
      self
    end

    def status(zone_id = 0)
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
      send "\x02\x06\xa0\x52" + zone + type + [other.to_i].pack('s>') + "\x00".b
      listen(:success)
      other
    end

    def volume
      volume_get(0)
    end

    def volume=(other)
      volume_set(0, other)
    end

    def volumes
      @volumes_proxy
    end

    def active_input_get(zone_id)
      current = status(zone_id)[:ch][:video]
      inputs[zone_id][current] || self.reload_input.inputs[zone_id][current]
    end

    def active_input_set(zone_id, other)
      new_input = if other.is_a?(Input)
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

    def active_inputs
      @active_inputs_proxy
    end

    def active_input
      active_input_get(0)
    end

    def active_input=(other)
      active_input_set(0, other)
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

    def get_input_list(zone_id, page = 0)
      send("\x02\x04\xa0\x8b".b + zone_id.chr('ASCII-8BIT') + page.chr('ASCII-8BIT') + "\x00".b)
    end

    def send(str)
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

        debug([:buffer_ramain, buffer]) if hit && !buffer.empty?
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

