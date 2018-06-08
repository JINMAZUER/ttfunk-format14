require 'yaml'

module TTFunk
  class Table
    class Cff < TTFunk::Table
      class Charset < TTFunk::SubTable
        include Enumerable

        DEFAULT_CHARSET_ID = 0
        FIRST_GLYPH_STRING = '.notdef'.freeze
        ISO_ADOBE_CHARSET_ID = 0
        EXPERT_CHARSET_ID = 1
        EXPERT_SUBSET_CHARSET_ID = 2

        CHARSET_FILES = {
          ISO_ADOBE_CHARSET_ID => 'iso_adobe.yml',
          EXPERT_CHARSET_ID => 'expert.yml',
          EXPERT_SUBSET_CHARSET_ID => 'expert_subset.yml'
        }.freeze

        class << self
          def standard_strings
            @standard_strings ||= YAML.load_file(
              ::File.expand_path(
                ::File.join(%w[. charsets standard_strings.yml]), __dir__
              )
            ).freeze
          end

          def strings_for_charset_id(charset_id)
            string_cache[charset_id] ||= YAML.load_file(
              ::File.expand_path(
                ::File.join('.', 'charsets', CHARSET_FILES.fetch(charset_id)),
                __dir__
              )
            ).freeze
          end

          private

          def string_cache
            @string_cache ||= {}
          end
        end

        attr_reader :top_dict, :format, :count, :offset_or_id

        def initialize(top_dict, file, offset_or_id = nil, length = nil)
          @top_dict = top_dict
          @offset_or_id = offset_or_id || DEFAULT_CHARSET_ID

          if offset
            super(file, offset, length)
          else
            @count = self.class.strings_for_charset_id(offset_or_id).size
          end
        end

        def each
          return to_enum(__method__) unless block_given?
          # +1 adjusts for the implicit .notdef glyph
          (count + 1).times { |i| yield self[i] }
        end

        def [](glyph_id)
          return FIRST_GLYPH_STRING if glyph_id == 0
          find_string(sid_for(glyph_id))
        end

        def offset
          # Numbers from 0..2 mean charset IDs instead of offsets. IDs are
          # basically pre-defined sets of characters.
          #
          # In the case of an offset, add the CFF table's offset since the
          # charset offset is relative to the start of the CFF table. Otherwise
          # return nil (no offset).
          if offset_or_id > 2
            offset_or_id + top_dict.cff_offset
          end
        end

        # mapping is new -> old glyph ids
        def encode(mapping)
          # no offset means no charset was specified (i.e. we're supposed to
          # use a predefined charset) so there's nothing to encode
          return '' unless offset

          sids = mapping.keys.sort.map { |new_gid| sid_for(mapping[new_gid]) }
          ranges = TTFunk::BinUtils.rangify(sids)
          range_max = ranges.map(&:last).max

          range_bytes = if range_max > 0
                          (Math.log2(range_max) / 8).floor + 1
                        else
                          # for cases when there are no sequences at all
                          Float::INFINITY
                        end

          # calculate whether storing the charset as a series of ranges is
          # more efficient (i.e. takes up less space) vs storing it as an
          # array of SID values
          total_range_size = (2 * ranges.size) + (range_bytes * ranges.size)
          total_array_size = sids.size * element_width(:array_format)

          [].tap do |result|
            if total_array_size <= total_range_size
              result << [format_int(:array_format)].pack('C')
              result << sids.pack('n*')
            else
              fmt = range_bytes == 1 ? :range_format_8 : :range_format_16
              element_fmt = element_format(fmt)
              result << [format_int(fmt)].pack('C')

              ranges.each do |range|
                sid, num_left = range
                result << [sid, num_left].pack(element_fmt)
              end
            end
          end.join
        end

        private

        def sid_for(glyph_id)
          return 0 if glyph_id == 0

          # rather than validating the glyph as part of one of the predefined
          # charsets, just pass it through
          return glyph_id unless offset

          case format_sym
          when :array_format
            # zero is always .notdef, so adjust with - 1
            @entries[glyph_id - 1]

          when :range_format_8, :range_format_16
            remaining = glyph_id

            @entries.each do |range|
              if range.size >= remaining
                return (range.first + remaining) - 1
              end

              remaining -= range.size
            end

            0
          end
        end

        def find_string(sid)
          if offset
            return self.class.standard_strings[sid - 1] if sid <= 390

            idx = sid - 390

            if idx < file.cff.string_index.count
              file.cff.string_index[idx - 1]
            end
          else
            self.class.strings_for_charset_id(offset_or_id)[sid - 1]
          end
        end

        def parse!
          return unless offset
          @format = read(1, 'C').first

          case format_sym
          when :array_format
            @count = top_dict.charstrings_index.count - 1
            @length = @count * element_width
            @entries = read(length, 'n*')

          when :range_format_8, :range_format_16
            # The number of ranges is not explicitly specified in the font.
            # Instead, software utilizing this data simply processes ranges
            # until all glyphs in the font are covered.
            @count = 0
            @entries = []
            @length = 0

            until @count >= top_dict.charstrings_index.count - 1
              @length += 1 + element_width
              sid, num_left = read(element_width, element_format)
              @entries << (sid..(sid + num_left))
              @count += num_left + 1
            end
          end
        end

        def element_width(fmt = format_sym)
          case fmt
          when :array_format then 2 # SID
          when :range_format_8 then 3 # SID + Card8
          when :range_format_16 then 4 # SID + Card16
          end
        end

        def element_format(fmt = format_sym)
          case fmt
          when :array_format then 'n'
          when :range_format_8 then 'nC'
          when :range_format_16 then 'nn'
          end
        end

        def format_sym(fmt = @format)
          case fmt
          when 0 then :array_format
          when 1 then :range_format_8
          when 2 then :range_format_16
          else
            raise "unsupported charset format '#{fmt}'"
          end
        end

        def format_int(sym = format_sym)
          case sym
          when :array_format then 0
          when :range_format_8 then 1
          when :range_format_16 then 2
          else
            raise "unsupported charset format '#{sym}'"
          end
        end
      end
    end
  end
end
