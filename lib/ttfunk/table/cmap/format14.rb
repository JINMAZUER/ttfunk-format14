# frozen_string_literal: true

module TTFunk
  class Table
    class Cmap
      module Format14
        attr_reader :language
        attr_reader :code_map

        def self.encode(charmap)
        end

        def [](code)
          base = code
          var_selector = 0
          if code.is_a?(Array)
            if code.length == 1
              base = code[0]
            elsif code.length == 2
              base = code[0]
              var_selector = code[1]
            end
          end
          if @code_map[base]
            @code_map[base][var_selector] || 0
          else
            0
          end
        end                

        def supported?
          true
        end

        private

        def parse_cmap!
          num_var_selector_records = read(8, 'x4N').first
        
          var_selector_records = []
        
          num_var_selector_records.times do
            var_selector_high, var_selector_mid, var_selector_low = read(3, 'CCC')
            var_selector = (var_selector_high << 16) | (var_selector_mid << 8) | var_selector_low
            default_uvs_offset, non_default_uvs_offset = read(8, 'NN')
            var_selector_records << {
              var_selector: var_selector,
              default_uvs_offset: default_uvs_offset,
              non_default_uvs_offset: non_default_uvs_offset
            }
          end

          # @code_map = $format12_cmap.dup
          @code_map = {}
          $format12_cmap.each do |k, v|
            @code_map[k] = { 0 => v }
          end

          var_selector_records.each do |record|
            if record[:default_uvs_offset] > 0
              parse_default_uvs_table(record[:var_selector])
            end

            if record[:non_default_uvs_offset] > 0
              parse_non_default_uvs_table(record[:var_selector])
            end
          end
        end
        
        def parse_default_uvs_table(var_selector)
          num_unicode_value_ranges = read(4, 'N').first
          unicode_ranges = []

          num_unicode_value_ranges.times do
            unicode_value_high, unicode_value_mid, unicode_value_low, additional_count = read(4, 'CCCC')
            unicode_value = (unicode_value_high << 16) | (unicode_value_mid << 8) | (unicode_value_low)

            unicode_ranges << {
              unicode_value: unicode_value,
              additional_count: additional_count
            }

            (0..additional_count).each do |i|
              @code_map[unicode_value + i] ||= {}
              @code_map[unicode_value + i][var_selector] = $format12_cmap[unicode_value]
            end
          end
        end
        
        def parse_non_default_uvs_table(var_selector)
          num_code_maps = read(4, 'N').first

          num_code_maps.times do
            unicode_value_high, unicode_value_mid, unicode_value_low, glyph_id = read(5, 'CCCn')
            unicode_value = (unicode_value_high << 16) | (unicode_value_mid << 8) | (unicode_value_low)

            @code_map[unicode_value] ||= {}
            @code_map[unicode_value][var_selector] = glyph_id
          end
        end
      end
    end
  end
end
