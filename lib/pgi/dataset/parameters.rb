require "pgi/dataset/utils"

module PGI
  module Dataset
    class Parameters
      Param = Struct.new(:key, :column, :index, :value, :type, keyword_init: true) do
        def typed_column
          "#{column}#{type_postfix}"
        end

        def typed_index
          "#{index}#{type_postfix}"
        end

        def type_postfix
          type_postfix = ""
          type_postfix = "::#{type}" if type
          type_postfix
        end
      end
      attr_reader :attributes

      def initialize(attributes, table: nil, starting_index: 1, attribute_pg_types: {})
        attributes = attributes.to_a.map do |k, v|
          { key: k, column: Utils.sanitize_column(k, table), value: v }
        end
        attributes = attributes.sort_by { |x, _| x[:key] }
        @attributes = attributes.map.with_index do |v, i|
          type = attribute_pg_types.fetch(v[:key], nil)
          Param.new(
            **v,
            index: "$#{i + starting_index}",
            type: type,
          )
        end
      end

      %i[key column index value typed_column typed_index].each do |field|
        define_method(:"by_#{field}") do
          @by_field ||= {}
          @by_field[field] ||= @attributes.to_h { |x| [x.send(field), x] }
        end

        define_method(:"#{field}s") do
          @all_of_field ||= {}
          @all_of_field[field] ||= @attributes.map { |x| x.send(field) }
        end
      end

      alias_method :indices, :indexs
      alias_method :typed_indices, :typed_indexs
      def length
        attributes.length
      end
    end
  end
end
