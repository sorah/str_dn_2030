module StrDn2030
  class Remote
    class Zone
      def initialize(parent, zone_id, volume_type = "\x03".b)
        @parent = parent
        @zone_id = zone_id
        @zone = zone_id.chr('ASCII-8BIT').freeze
        @volume_type = volume_type.dup.b.freeze
      end

      attr_reader :parent, :zone_id, :zone, :volume_type
      alias id zone_id

      def reload
        parent.reload; self
      end

      def inputs
        parent.inputs[zone_id]
      end

      def powered_on?
        parent.status_get(zone_id)[:flags][:power]
      end

      def muted?
        parent.status_get(zone_id)[:flags][:mute]
      end

      def headphone?
        parent.status_get(zone_id)[:flags][:headphone]
      end

      def volume
        parent.volume_get(zone_id, volume_type)[:volume]
      end

      def volume=(other)
        parent.volume_set(zone_id, other, volume_type)
      end

      def active_video
        parent.active_input_get(zone_id)
      end

      def active_video=(other)
        parent.active_input_set(zone_id, other)
      end

      alias active_input  active_video
      alias active_input= active_video=
    end
  end
end
