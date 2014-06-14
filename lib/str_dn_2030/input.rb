module StrDn2030
  class Input
    def initialize(parent, zone, index, audio, video, icon, preset_name, name, skip)
      @parent = parent
      @zone = zone
      @index = index.dup.b.freeze
      @audio = audio.dup.b.freeze
      @video = video.dup.b.freeze
      @icon = icon.dup.b.freeze
      @preset_name = preset_name.strip.freeze
      @name = name.strip.freeze
      @skip_flags = skip.dup.b.freeze
    end

    attr_reader :parent,
      :zone, :index,
      :audio, :video,
      :icon,
      :preset_name, :name,
      :skip_flags

    def inspect
      "#<#{self.class.name}: #{name} @ #{parent.host}:#{parent.port}/#{zone}>"
    end

    def activate!
      parent.active_input = self
      nil
    end

    def active?
      parent.zone(self.zone).active_input == self
    end

    def skipped?
      skip[:watch] && skip[:listen]
    end

    def watch_skipped?
      skip[:watch]
    end

    def listen_skipped?
      skip[:listen]
    end

    def skipped_any?
      skip[:watch] || skip[:listen]
    end

    def skip
      @skip ||= begin
        {raw: skip_flags}.tap do |_|
          _.merge!({
            "\x11".b => {watch: true,  listen: true},
            "\x21".b => {watch: true,  listen: true},
            "\x30".b => {watch: false, listen: false},
            "\x10".b => {watch: false, listen: true},
            "\x20".b => {watch: true,  listen: false},
          }[skip_flags.b] || {})
        end
      end
    end

    def ==(other)
      other.is_a?(self.class) && self.video == other.video && self.audio == other.audio
    end

    def as_json
      {
        zone: zone,
        index: index,
        audio: audio,
        video: video,
        icon: icon,
        preset_name: preset_name,
        name: name,
        skip: skip,
        active: active?,
      }
    end
  end
end
