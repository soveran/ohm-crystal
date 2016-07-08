# Copyright (c) 2016 Michel Martens
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
require "nest"
require "stal"
require "json"

module Ohm
  class MissingID < Exception
  end

  class IndexNotFound < Exception
  end

  class RecordNotFound < Exception
  end

  class UniqueIndexViolation < Exception
    PATTERN = /(UniqueIndexViolation: (\w+))/
  end

  class NoScript < Exception
    PATTERN = /NOSCRIPT/
  end

  alias Filter = Hash(String, String | Array(String))

  class Finder(M, T)
    getter model : M
    getter key : Nest
    getter expr : T
    getter indices : Set(String)

    def initialize(@model, @key, @indices, @expr)
    end

    def as_index(name : String, value : String)
      [key["indices"][name][value].to_s]
    end

    def as_index(name : String, values : Array(String))
      values.map do |value|
        key["indices"][name][value].to_s
      end
    end

    def express(filter : Filter)
      filter.map do |name, value|
        unless indices.includes?(name)
          raise IndexNotFound.new(name)
        end

        as_index(name, value)
      end.flatten
    end

    def includes?(id : Nil)
      false
    end

    def includes?(id : String)
      solve(["SISMEMBER", expr, id]) == 1
    end

    def includes?(object : Ohm::Model)
      includes?(object.id)
    end

    def includes?(id)
      includes?(id.to_s)
    end

    def size
      solve(["SCARD", expr])
    end

    def ids
      solve(expr).as(Array(Resp::Reply))
    end

    def model
      @model
    end

    def to_a
      model.fetch(ids)
    end

    def find(filter : Filter)
      expr = ["SINTER", expr].concat(express(filter))
      Finder(M, typeof(expr)).new(model, key, indices, expr)
    end

    def union(filter : Filter)
      expr = ["SUNION", expr, ["SINTER"].concat(express(filter))]
      Finder(M, typeof(expr)).new(model, key, indices, expr)
    end

    def except(filter : Filter)
      expr = ["SDIFF", expr, ["SUNION"].concat(express(filter))]
      Finder(M, typeof(expr)).new(model, key, indices, expr)
    end

    def combine(filter : Filter)
      expr = ["SINTER", expr, ["SUNION"].concat(express(filter))]
      Finder(M, typeof(expr)).new(model, key, indices, expr)
    end

    private def solve(expr : Array)
      Stal.solve(Ohm.redis, expr)
    end

    private def solve(expr : String)
      solve(["SMEMBERS", expr])
    end
  end

  abstract class Model
    getter id : String?
    getter attributes : Hash(String, String)

    @counters : Nest?
    @attributes = Hash(String, String).new
    @@attributes = Set(String).new
    @@indices = Set(String).new
    @@uniques = Set(String).new
    @@tracked = Set(String).new

    macro with_file(filename, command)
      {% dir = system("dirname", __FILE__).strip %}
      {{ system(command, dir + "/" + filename).stringify }}
    end

    LUA = {
      save: {
        src: with_file("ohm/save.lua", "cat"),
        sha: with_file("ohm/save.lua", "shasum").split(' ').first,
      },

      delete: {
        src: with_file("ohm/delete.lua", "cat"),
        sha: with_file("ohm/delete.lua", "shasum").split(' ').first,
      },
    }

    def self.redis
      Ohm.redis
    end

    def self.key
      Nest.new(name, redis)
    end

    def self.attributes
      @@attributes
    end

    def self.indices
      @@indices
    end

    def self.uniques
      @@uniques
    end

    def self.tracked
      @@tracked
    end

    macro attribute(name)
      attributes.add({{name.id.stringify}})

      def {{name.id}}
        attributes[{{name.id.stringify}}]?
      end

      def {{name.id}}=(value)
        attributes[{{name.id.stringify}}] = value.to_s
      end
    end

    def counters
      @counters ||= key["counters"]
    end

    macro counter(name)
      def {{name.id}}(n = "0")
        counters.call("HINCRBY", {{name.id.stringify}}, n.to_s)
      end
    end

    macro reference(name, model)
      attribute :{{name.id}}_id
      index     :{{name.id}}_id

      def {{name.id}}=(instance)
        self.{{name.id}}_id = instance.id
      end

      def {{name.id}}
        {{model.id}}[{{name.id}}_id]
      end
    end

    macro collection(name, model, reference)
      def {{name.id}}
        {{model.id}}.find({ {{reference.id.stringify}} => id as String })
      end
    end

    abstract class MutableCollection(M)
      getter model : M
      getter key : Nest

      def initialize(@model, @key)
      end

      abstract def size
      abstract def includes?(object)
      abstract def ids

      def to_a
        model.fetch(ids)
      end

      def redis
        model.redis
      end
    end

    class MutableSet(M) < MutableCollection(M)
      def size
        key.call("SCARD")
      end

      def add(object)
        key.call("SADD", object.id.to_s)
      end

      def delete(object)
        key.call("SREM", object.id.to_s)
      end

      def includes?(object)
        key.call("SISMEMBER", object.id.to_s) == 1
      end

      def ids
        key.call("SMEMBERS").as(Array(Resp::Reply))
      end
    end

    class MutableList(M) < MutableCollection(M)
      def size
        key.call("LLEN")
      end

      def push(object)
        key.call("RPUSH", object.id.to_s)
      end

      def unshift(object)
        key.call("LPUSH", object.id.to_s)
      end

      def delete(object)
        key.call("LREM", "0", object.id.to_s)
      end

      def ids
        key.call("LRANGE", "0", "-1").as(Array(Resp::Reply))
      end

      def includes?(object)
        ids.includes?(object.id.to_s)
      end
    end

    macro mutable(name, model, type)
      def {{name.id}}
        @{{name.id}} ||= {{type.id}}({{model.id}}.class).new(
          {{model.id}}, key[{{name.id.stringify}}])
      end
    end

    macro set(name, model)
      mutable({{name}}, {{model}}, MutableSet)
    end

    macro list(name, model)
      mutable({{name}}, {{model}}, MutableList)
    end

    macro index(name)
      indices.add({{name.id.stringify}})
    end

    macro unique(name)
      uniques.add({{name.id.stringify}})
    end

    macro track(name)
      tracked.add({{name.id.stringify}})
    end

    def self.as_index(name : String, value : String)
      [key["indices"][name][value].to_s]
    end

    def self.as_index(name : String, values : Array(String))
      values.map do |value|
        key["indices"][name][value].to_s
      end
    end

    def self.as_indices(filter : Hash(String, String | Array(String)))
      filter.map do |name, value|
        unless indices.includes?(name)
          raise IndexNotFound.new(name)
        end

        as_index(name, value)
      end.flatten
    end

    def self.find(filter : Hash(String, String | Array(String)))
      expr = ["SINTER"].concat(as_indices(filter))
      Finder(self.class, typeof(expr)).new(self, key, indices, expr)
    end

    def self.with(name, value)
      unless uniques.includes?(name)
        raise IndexNotFound.new(name)
      end

      id = redis.call("HGET", key["uniques"][name].to_s, value)
      new(id.as(String)).retrieve! if id
    end

    def self.all
      Finder(self.class, String).new(self, key, indices, key["all"].to_s)
    end

    def self.includes?(id : String)
      all.includes?(id)
    end

    def self.includes?(id : Int)
      includes?(id.to_s)
    end

    def self.[](id : String)
      if includes?(id)
        new(id).retrieve!
      else
        raise RecordNotFound.new(id)
      end
    end

    def self.[](id : Int)
      self[id.to_s]
    end

    def self.[](id : Nil)
      nil
    end

    def self.fetch(ids : Array(Resp::Reply))
      ids.each do |id|
        redis.queue("HGETALL", key[id].to_s)
      end

      redis.commit.map_with_index do |atts, i|
        new(ids[i].to_s).merge(atts.as(Array(Resp::Reply)))
      end
    end

    def self.create
      new.save
    end

    def self.create(atts)
      new(atts).save
    end

    def initialize
    end

    def initialize(atts : Hash(String, String))
      merge(atts)
    end

    private def initialize(@id : String)
    end

    def model
      self.class
    end

    def redis
      model.redis
    end

    def key
      raise MissingID.new unless id
      model.key[id]
    end

    def ==(other : self)
      key.to_s == other.key.to_s
    end

    def ==(other)
      false
    end

    def retrieve!
      merge(redis.call(["HGETALL", key.to_s]).as(Array(Resp::Reply)))
    end

    def save
      indices = Hash(String, Array(String)).new
      uniques = Hash(String, String).new

      atts = Array(String).new

      model.attributes.each do |att|
        next unless val = attributes[att]?

        if model.indices.includes?(att)
          indices[att] = [val]
        end

        if model.uniques.includes?(att)
          uniques[att] = val
        end

        atts.push(att, val)
      end

      features = {"name" => model.name}
      features["id"] = id.to_s if id

      @id = script(:save, "0",
        features.to_json,
        atts.to_json,
        indices.to_json,
        uniques.to_json,
      ).as(String)

      self
    end

    def delete
      uniques = Hash(String, String).new
      tracked = model.tracked

      model.uniques.each do |att|
        if attributes[att]?
          uniques[att] = attributes[att]
        end
      end

      features = {
        "name" => model.name,
        "id"   => id.to_s,
        "key"  => key.to_s,
      }

      script(:delete, "0",
        features.to_json,
        uniques.to_json,
        tracked.to_json,
      )

      self
    end

    def merge(atts : Array(Resp::Reply))
      atts.each_slice(2) do |slice|
        @attributes[slice[0].to_s] = slice[1].to_s
      end

      self
    end

    def merge(atts : Hash(String, String))
      atts.each do |name, value|
        if model.attributes.includes?(name)
          @attributes[name] = value
        end
      end

      self
    end

    def update(atts : Hash(String, String))
      merge(atts) && save
    end

    private def script(action, *args)
      begin
        redis.call("EVALSHA", LUA[action][:sha], *args)
      rescue ex : Exception
        case ex.message
        when NoScript::PATTERN
          redis.call("SCRIPT", "LOAD", LUA[action][:src])
          redis.call("EVALSHA", LUA[action][:sha], *args)
        when UniqueIndexViolation::PATTERN
          raise UniqueIndexViolation.new($1)
        else
          raise ex
        end
      end
    end
  end

  def self.redis=(@@redis : Resp)
  end

  def self.redis
    @@redis ||= Resp.new("redis://localhost:6379")
  end
end
