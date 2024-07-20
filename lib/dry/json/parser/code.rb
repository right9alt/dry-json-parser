require 'dry-struct'
require 'dry-types'
require 'json'
require 'pp'

module Types
  include Dry.Types()
end

class DeliveryMethodValue < Dry::Struct
  attribute :id, Types::Integer
  attribute :name, Types::String
end

class PrizeValue < Dry::Struct
  attribute :name, Types::String
  attribute :sku, Types::Integer
end

class ProductValue < Dry::Struct

  attribute :prizes, Types::Array.of(PrizeValue)
  attribute :name, Types::String
  attribute :sku, Types::Integer
  attribute :dimensions__height, Types::Integer

end

class PostingValue < Dry::Struct
  attribute :posting_number, Types::String
  attribute :order_id, Types::Integer
  attribute :delivery_method, DeliveryMethodValue
  attribute :products, Types::Array.of(ProductValue)
  attribute :integers, Types::Array.of(Types::Integer)
end

# Example JSON data
json_array_data = '{
  "result": {
    "postings": [
      {
        "posting_number": "02329461-0607-1",
        "order_id": 24428352933,
        "delivery_method": {
          "id": 1020001268365000,
          "name": "Доставка Ozon самостоятельно, Тверь"
        },
        "products": [
          {
            "prizes": [
              {
                "name": "Serenada платье френда, сине-голубой",
                "sku": 1582970997
              }
            ],
            "name": "Serenada платье френда, сине-голубой",
            "sku": 1582970997
          }
        ],
        "integers": [1,2,3,4]
      },
      {
        "posting_number": "02329461-0608-1",
        "order_id": 24428362933,
        "delivery_method": {
          "id": 1020001268365000,
          "name": "Доставка Ozon самостоятельно, Тверь"
        },
        "products": [
          {
            "prizes": [
              {
                "name": "Serenada платье дакота, голубой",
                "sku": 1567902027
              }
            ],
            "name": "Serenada платье дакота, голубой",
            "sku": 1567902027
          }
        ],
        "integers": [1,2,3,4]
      }
    ]
  }
}'

json_single_data = '{
  "result": {
    "posting_number": "02329461-0607-1",
    "order_id": 24428352933,
    "delivery_method": {
      "id": 1020001268365000,
      "name": "Доставка Ozon самостоятельно, Тверь"
    },
    "products": [
      {
        "prizes": [
          {
            "name": "Serenada платье френда, сине-голубой",
            "sku": 1582970997
          }
        ],
        "name": "Serenada платье френда, сине-голубой",
        "sku": 1582970997,
        "dimensions": {
          "height": 123
        }
      }
    ],
    "integers": [1,2,3,4]
  }
}'

# Parsing JSON
json_array = JSON.parse(json_array_data)
json_single = JSON.parse(json_single_data)

# Функция для извлечения внутреннего примитивного типа из сложных типов
def extract_primitive_type(type)
  while type.respond_to?(:type)
    type = type.type
  end

  type.primitive
end

# Рекурсивная функция для построения карты типов
def build_type_map(schema)
  type_map = {}

  schema.keys.each do |attr|
    inner_type = extract_primitive_type(attr.type)
    name = attr.name
    if inner_type == Array
      element_type = extract_primitive_type(attr.type.member)
      type_map[name] = { type: element_type, is_array: true, custom: element_type.respond_to?(:schema) }
    else
      type_map[name] = { type: inner_type, is_array: false, custom: inner_type.respond_to?(:schema) }
    end
    type_map[name][:path] = name.to_s.split("__") if name.to_s.include? "__"
  end
  type_map
end

# Функция для построения полной карты типов, включая вложенные пользовательские типы
def build_full_type_map(klass:)
  main_map = build_type_map(klass.schema)
  nested_maps = {}

  main_map.each do |name, details|
    if details[:custom]
      nested_maps[name] = details.merge(mapping: build_full_type_map(klass: details[:type]))
    end
  end

  main_map.merge(nested_maps)
end

def create_struct_from_hash(klass, json, type_map)
  attributes =
    klass.schema.keys.map(&:name).each_with_object({}) do |key, hash|
      nested_type_map = type_map[:mapping][key]
      json_value = 
        if nested_type_map[:path]
          json.dig(*nested_type_map[:path])
        else
          json[key.to_s]
        end

      hash[key] =
        if nested_type_map[:custom]
          if nested_type_map[:is_array]
            json_value.map { create_struct_from_hash(nested_type_map[:type], _1, nested_type_map) }
          else
            create_struct_from_hash(nested_type_map[:type], json_value, nested_type_map)
          end
        else
          json_value
        end
    end

  klass.new(attributes.compact)
end

def parse_to_struct(klass, json)
  type_map = { mapping: build_full_type_map(klass: PostingValue) }
  pp type_map # TODO: REMOVE

  if json.is_a?(Array)
    json.map { create_struct_from_hash(PostingValue, _1, type_map) }
  else
    create_struct_from_hash(PostingValue, json, type_map)
  end
end

dry_struct = parse_to_struct(PostingValue, json_single["result"])
#dry_struct = parse_to_struct(PostingValue, json_array["result"]["postings"])

pp dry_struct

# {:posting_number=>{:type=>String, :is_array=>false, :custom=>false},
#  :order_id=>{:type=>Integer, :is_array=>false, :custom=>false},
#  :delivery_method=>
#   {:type=>DeliveryMethodValue,
#    :is_array=>false,
#    :custom=>true,
#    :id=>{:type=>Integer, :is_array=>false, :custom=>false},
#    :name=>{:type=>String, :is_array=>false, :custom=>false}},
#  :products=>
#   {:type=>ProductValue,
#    :is_array=>true,
#    :custom=>true,
#    :prizes=>
#     {:type=>PrizeValue,
#      :is_array=>true,
#      :custom=>true,
#      :name=>{:type=>String, :is_array=>false, :custom=>false},
#      :sku=>{:type=>Integer, :is_array=>false, :custom=>false}},
#    :name=>{:type=>String, :is_array=>false, :custom=>false},
#    :sku=>{:type=>Integer, :is_array=>false, :custom=>false}},
#  :integers=>{:type=>Integer, :is_array=>true, :custom=>false}}
# botrac@MacBook-Pro dry-json-parser % 
