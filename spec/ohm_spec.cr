require "./spec_helper"

describe "Ohm" do
  before do
    Ohm.redis = Resp.new("redis://localhost:6379")
    Ohm.redis.call("FLUSHDB")
    Ohm.redis.call("SCRIPT", "FLUSH")
  end

  class Foo < Ohm::Model
    attribute "a"
    attribute "b"
    attribute "c"
    attribute "d"

    index "a"
    index "b"

    unique "d"

    collection "bars", Bar, "foo_id"
  end

  class Bar < Ohm::Model
    attribute "a"

    counter "b"

    unique "a"

    reference "foo", Foo

    set  "xs", Bar
    list "ys", Bar
  end

  it "should have a key" do
    assert_equal "Foo",   Foo.key.to_s
    assert_equal "Foo:1", Foo.key[1].to_s
  end

  it "should define attributes, indices and uniques" do
    assert_equal Set{"a", "b", "c", "d"}, Foo.attributes
    assert_equal Set{"a", "b"},           Foo.indices
    assert_equal Set{"d"},                Foo.uniques
  end

  it "should accept a hash with attributes" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.new(atts)

    assert_equal atts, foo.attributes

    assert_equal "1", foo.a
    assert_equal "2", foo.b
    assert_equal "3", foo.c
    assert_equal "4", foo.d
  end

  it "should provide setters" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.new(atts)
    foo.a = "2"

    assert_equal "2", foo.a
  end

  it "should have a nil id when new" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.new(atts)

    assert_equal nil, foo.id
  end

  it "should raise when trying to use #key when new" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.new(atts)

    assert_raise(Ohm::MissingID) do
      foo.key
    end
  end

  it "should persist the attributes when saved" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.new(atts)

    foo.save

    assert_equal "1",     foo.id
    assert_equal "Foo:1", foo.key.to_s
    assert_equal "hash",  foo.key.call("TYPE")

    foo2 = Foo[foo.id as String]

    assert_equal foo.key.to_s, foo2.key.to_s
    assert_equal foo, foo2

    assert foo2 != nil
    assert_equal "1", foo2.id
    assert_equal "1", foo2.a
    assert_equal "2", foo2.b
    assert_equal "3", foo2.c
    assert_equal "4", foo2.d
  end

  it "should create a new instance" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_equal "1", foo.id
  end

  it "should have a set of all ids" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_equal ["1"], Foo.all.ids
  end

  it "should find instances by indexed attributes" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert Foo[1] != nil

    assert_raise(Ohm::RecordNotFound) do
      Foo[2]
    end

    finder = Foo.find({ "a" => "1", "b" => "2" })

    assert_equal false, finder.includes?(nil)
    assert_equal false, finder.includes?(2)
    assert_equal true,  finder.includes?(foo.id)
    assert_equal true,  finder.includes?(foo)

    assert_equal 1, finder.size

    foo2 = finder.to_a.first

    assert_equal "1", foo2.id
  end

  it "should raise if trying to search an unindexed attribute" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_raise(Ohm::IndexNotFound) do
      Foo.find({ "c" => "3" })
    end
  end

  it "should chain finders" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    finder = Foo.find({ "a" => "1" }).find({ "b" => "2" })
    assert_equal ["1"], finder.to_a.map(&.id)

    finder = Foo.find({ "a" => "1" }).except({ "b" => "2" })
    assert_equal true,  finder.to_a.map(&.id).empty?

    finder = Foo.find({ "a" => "1" }).combine({ "b" => "2" })
    assert_equal false, finder.to_a.map(&.id).empty?
  end

  it "should search by unique" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    foo2 = Foo.with("d", "4")

    assert foo2 != nil

    if foo2
      assert_equal "1", foo2.id
    end
  end

  it "should raise if trying to save a duplicate unique attribute" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_raise(Ohm::UniqueIndexViolation) do
      Foo.create(atts)
    end
  end

  it "should allow references and collections" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)
    bar = Bar.create({ "a" => "1" })

    bar.foo = foo
    bar.save

    assert_equal "1", bar.foo_id

    foo2 = bar.foo

    assert foo2 != nil

    if foo2
      assert_equal "1", foo2.id
    end

    assert foo.bars.includes?(bar)
  end

  it "should allow sets" do
    bar1 = Bar.create({ "a" => "1" })
    bar2 = Bar.create({ "a" => "2" })
    bar3 = Bar.create({ "a" => "3" })

    bar1.xs.add(bar2)

    assert_equal 1, bar1.xs.size
    assert_equal true, bar1.xs.includes?(bar2)
    assert_equal false, bar1.xs.includes?(bar3)
    assert_equal ["2"], bar1.xs.ids
    assert_equal [bar2], bar1.xs.to_a
  end

  it "should allow lists" do
    bar1 = Bar.create({ "a" => "1" })
    bar2 = Bar.create({ "a" => "2" })
    bar3 = Bar.create({ "a" => "3" })

    bar1.ys.push(bar2)

    assert_equal 1, bar1.ys.size
    assert_equal true, bar1.ys.includes?(bar2)
    assert_equal false, bar1.ys.includes?(bar3)
    assert_equal ["2"], bar1.ys.ids
    assert_equal [bar2], bar1.ys.to_a
  end

  it "should delete lists" do
    bar1 = Bar.create({ "a" => "1" })
    bar2 = Bar.create({ "a" => "2" })
    bar3 = Bar.create({ "a" => "3" })

    bar1.ys.push(bar2)

    assert_equal 1, bar1.ys.size
    assert_equal true, bar1.ys.includes?(bar2)
    assert_equal false, bar1.ys.includes?(bar3)
    assert_equal ["2"], bar1.ys.ids
    assert_equal [bar2], bar1.ys.to_a
  end

  it "should update an instance" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_equal "1", foo.id
    assert_equal "1", foo.a

    # Extra attributes, like "g", are ignored
    foo.update({ "a" => "2", "g" => "5" })

    assert_equal "2", foo.a
    assert_equal "2", Foo[1].a
  end

  it "should delete an instance" do
    atts = { "a" => "1", "b" => "2", "c" => "3", "d" => "4" }

    foo = Foo.create(atts)

    assert_equal "1", foo.id

    foo.delete

    assert_equal ["Foo:id"], Ohm.redis.call("KEYS", "*")
  end

  it "should allow counters" do
    bar = Bar.create

    assert_equal 0, bar.b

    bar.b(+1)

    assert_equal 1, bar.b

    bar.b(-1)

    assert_equal 0, bar.b
  end

  class Log < Ohm::Model
    track "text"

    def append(msg)
      key["text"].call("APPEND", msg)
    end

    def tail(n = 100)
      key["text"].call("GETRANGE", "#{-n}", "-1")
    end
  end

  it "should work with tracked keys" do
    log = Log.create

    log.append("hello\n")

    assert_equal "hello\n", log.tail

    log.append("world\n")

    assert_equal "world\n", log.tail(6)

    log.delete

    assert_equal ["Log:id"], Ohm.redis.call("KEYS", "*")
  end
end


describe "Finder" do
  class Baz < Ohm::Model
    attribute "a"
    attribute "b"

    index "a"
    index "b"
  end

  it "should be combinable" do
    u1 = Baz.create({ "a" => "1", "b" => "1" })
    u2 = Baz.create({ "a" => "1", "b" => "2" })
    u3 = Baz.create({ "a" => "2", "b" => "1" })
    u4 = Baz.create({ "a" => "2", "b" => "2" })

    f1 = Baz.find({ "a" => "1" })
    f2 = Baz.find({ "a" => "1", "b" => "1" })
    f3 = Baz.find({ "b" => "1" }).combine({ "a" => ["1", "2"] })
    f4 = Baz.find({ "a" => "1" }).except({ "b" => "2" })
    f5 = Baz.find({ "a" => "1" }).union({ "a" => "2" })
    f6 = Baz.find({ "a" => "1" }).union({ "b" => "2" })

    assert_equal f1.ids, ["1", "2"]
    assert_equal f2.ids, ["1"]
    assert_equal f3.ids, ["1", "3"]
    assert_equal f4.ids, ["1"]
    assert_equal f5.ids, ["1", "2", "3", "4"]
    assert_equal f6.ids, ["1", "2", "4"]
  end
end