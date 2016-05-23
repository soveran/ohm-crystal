Ohm ॐ
=====

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library for storing objects in [Redis][redis], a persistent key-value
database. It has very good performance.

Community
---------

Meet us on IRC: [#ohm](irc://chat.freenode.net/#ohm) on
[freenode.net](http://freenode.net/).

Related projects
----------------

These are libraries in other languages that were inspired by Ohm.

* [Ohm](https://github.com/soveran/ohm) for Ruby, created by soveran
* [JOhm](https://github.com/xetorthio/johm) for Java, created by xetorthio
* [Lohm](https://github.com/slact/lua-ohm) for Lua, created by slact
* [ohm.lua](https://github.com/amakawa/ohm.lua) for Lua, created by amakawa
* [Nohm](https://github.com/maritz/nohm) for Node.js, created by maritz
* [Redisco](https://github.com/iamteem/redisco) for Python, created by iamteem
* [redis3m](https://github.com/luca3m/redis3m) for C++, created by luca3m
* [Ohmoc](https://github.com/seppo0010/ohmoc) for Objective-C, created by seppo0010
* [Sohm](https://github.com/xxuejie/sohm.lua) for Lua, compatible with Twemproxy

Articles and Presentations
--------------------------

* [Simplicity](http://files.soveran.com/simplicity)
* [How to Redis](http://www.paperplanes.de/2009/10/30/how_to_redis.html)
* [Redis and Ohm](http://carlopecchia.eu/blog/2010/04/30/redis-and-ohm-part1/)
* [Ohm (Redis ORM)](http://blog.s21g.com/articles/1717) (Japanese)
* [Redis and Ohm](http://www.slideshare.net/awksedgreep/redis-and-ohm)
* [Ruby off Rails](http://www.slideshare.net/cyx.ucron/ruby-off-rails)
* [Data modeling with Redis and Ohm](http://www.sitepoint.com/semi-relational-data-modeling-redis-ohm/)

Getting started
---------------

Install [Redis][redis]. On most platforms it's as easy as grabbing the sources,
running make and then putting the `redis-server` binary in the PATH.

Once you have it installed, you can execute `redis-server` and it will
run on `localhost:6379` by default. Check the `redis.conf` file that comes
with the sources if you want to change some settings.

Add this to your application's `shard.yml`:

```yaml
dependencies:
  ohm:
    github: soveran/ohm-crystal
```

Or you can grab the code from [http://github.com/soveran/ohm-crystal][ohm].

## Connecting to a Redis database

Ohm uses a lightweight Redis client called [Resp][resp]. To connect
to a Redis database, you will need to set an instance of `Resp`, with
an URL of the form `redis://:<passwd>@<host>:<port>/<db>`, through the
`Ohm.redis=` method, e.g.

```crystal
require "ohm"

Ohm.redis = Resp.new("redis://127.0.0.1:6379")

Ohm.redis.call "SET", "Foo", "Bar"

Ohm.redis.call "GET", "Foo"
# => "Bar"
```

Ohm defaults to a Resp connection to "redis://127.0.0.1:6379". The
example above could be rewritten as:

```crystal
require "ohm"

Ohm.redis.call "SET", "Foo", "Bar"

Ohm.redis.call "GET", "Foo"
# => "Bar"
```

All Ohm models inherit the same connection settings from `Ohm.redis`.

Models
------

Ohm's purpose in life is to map objects to a key value datastore. It
doesn't need migrations or external schema definitions. Take a look at
the example below:

### Example

```crystal
class Party < Ohm::Model
  attribute "name"
  reference "venue", Venue
  set "participants", Person
  counter "votes"

  index "name"
end

class Venue < Ohm::Model
  attribute "name"
  collection "parties", Party, "venue_id"
end

class Person < Ohm::Model
  attribute "name"
end
```

All models have the `id` attribute built in, you don't need to declare it.

This is how you interact with IDs:

```crystal
party = Party.create({"name": "Ohm Worldwide Party 2031"})
party.id
# => "1"

# Find an party by id
party == Party[1]
# => true

# Update an party
party.update({"name": "Ohm Worldwide Party 2032"})
party.name
# => "Ohm Worldwide Party 2032"

# Trying to find a non existent party
Party[2]
# => nil

# Finding all the parties
Party.all.to_a

```

This example shows some basic features, like attribute declarations
and querying. Keep reading to find out what you can do with models.

Attribute types
---------------

Ohm::Model provides 4 attribute types:

* `Ohm::Model.attribute`,
* `Ohm::Model.set`
* `Ohm::Model.list`
* `Ohm::Model.counter`

and 2 meta types:

* `Ohm::Model.reference`
* `Ohm::Model.collection`.

### attribute

An `attribute` is just any value that can be stored as a string.
In the example above, we used this field to store the event's `name`.
If you want to store any other data type, you have to convert it
to a string first. Be aware that Redis will return a string when
you retrieve the value.

### set

A `set` in Redis is an unordered list, with an external behavior
similar to that of Ruby arrays, but optimized for faster membership
lookups.  It's used internally by Ohm to keep track of the instances
of each model and for generating and maintaining indexes.

### list

A `list` is like an array in Ruby. It's perfectly suited for queues
and for keeping elements in order.

### counter

A `counter` is like a regular attribute, but the direct manipulation
of the value is not allowed. You can retrieve, increase or decrease
the value, but you can not assign it. In the example above, we used
a counter attribute for tracking votes. As the increment and decrement
operations are atomic, you can rest assured a vote won't be counted
twice.

### reference

It's a special kind of attribute that references another model.
Internally, Ohm will keep a pointer to the model (its ID), but you
get accessors that give you real instances. You can think of it as
the model containing the foreign key to another model.

### collection

Provides an accessor to search for all models that `reference` the
current model.

Tracked keys
------------

Besides the provided attribute types, it is possible to instruct
Ohm to track arbitrary keys and tie them to the object's lifecycle.

For example:

```crystal
class Log < Ohm::Model
  track :text

  def append(msg)
    key["text"].call("APPEND", msg)
  end

  def tail(n = 100)
    key["text"].call("GETRANGE", -n.to_s, "-1")
  end
end

log = Log.create
log.append("hello\n")

assert_equal "hello\n", log.tail

log.append("world\n")

assert_equal "world\n", log.tail(6)
```

When the `log` object is deleted, the `:text` key will be deleted
too. Note that the key is scoped to that particular instance of
`Log`, so if `log.id` is `42` then the key will be `Log:42:text`.

Persistence strategy
--------------------

The attributes declared with `attribute` are only persisted after
calling `save`.

Operations on attributes of type `list`, `set` and `counter` are
possible only after the object is created (when it has an assigned
`id`). Any operation on these kinds of attributes is performed
immediately.  This design yields better performance than buffering
the operations and waiting for a call to `save`.

For most use cases, this pattern doesn't represent a problem.
If you are saving the object, this will suffice:

```crystal
if party.save
  party.comments.add(Comment.create({ "body" => "Wonderful event!" }))
end
```

Working with Sets
-----------------

Given the following model declaration:

```crystal
class Party < Ohm::Model
  attribute :name
  set :attendees, Person
end
```

You can add instances of `Person` to the set of attendees with the
`add` method:

```crystal
party.attendees.add(Person.create({ { "name" => "Albert" }))

# And now...
party.attendees.each do |person|
  # ...do what you want with this person.
end
```

Working with Lists
------------------

Given the following model declaration:

```crystal
class Queue < Ohm::Model
  attribute :name
  list :people, Person
end
```

You can add instances of `Person` to the list of people with the
`push` method:

```crystal
queue.people.push(Person.create({ { "name" => "Albert" }))

# And now...
queue.people.each do |person|
  # ...do what you want with this person.
end
```

Working with Counters
---------------------

Given the following model declaration:

```crystal
class Site < Ohm::Model
  attribute :url
  counter :visits
end
```

You can increment or decrement the visits:

```crystal
site.visits     #=> 0
site.visits(+1) #=> 1
site.visits(+1) #=> 2
site.visits(+5) #=> 7
site.visits(-4) #=> 3
site.visits     #=> 3
```

Associations
------------

Ohm lets you declare `references` and `collections` to represent
associations.

```crystal
class Post < Ohm::Model
  attribute :title
  attribute :body
  collection :comments, Comment, :post_id
end

class Comment < Ohm::Model
  attribute :body
  reference :post, Post
end
```

After this, every time you refer to `post.comments` you will be
talking about instances of the model `Comment`. If you want to get
a list of IDs you can use `post.comments.ids`.

### References explained

Doing a `Ohm::Model.reference` is actually just a shortcut for
the following:

```crystal
# Redefining our model above
class Comment < Ohm::Model
  attribute :body
  attribute :post_id
  index :post_id

  def post=(post)
    self.post_id = post.id
  end

  def post
    Post[post_id]
  end
end
```

The net effect here is we can conveniently set and retrieve `Post` objects,
and also search comments using the `post_id` index.

```crystal
Comment.find({ "post_id" => "1" })
```

### Collections explained

The reason a `Ohm::Model.reference` and a
`Ohm::Model.collection` go hand in hand, is that a collection is
just a macro that defines a finder for you, and we know that to find a model
by a field requires an `Ohm::Model.index` to be defined for the field
you want to search.

Here's again the `collection` macro in use:

```crystal
collection :comments, Comment, :post_id
```

When it expands, what you get is this method definition:

```crystal
def comments
  Comment.find({ "post_id" => self.id })
end
```

Both examples are equivalent.

Indices
-------

An `Ohm::Model.index` is a set that's handled automatically by Ohm. For
any index declared, Ohm maintains different sets of objects IDs for quick
lookups.

In the `Party` example, the index on the name attribute will
allow for searches like `Party.find({ "name" => "some value" })`.

Note that the methods `Ohm::Model::Set#find` and
`Ohm::Model::Set#except` need a corresponding index in order to work.

### Finding records

You can find a collection of records with the `find` method:

```crystal
# This returns a collection of users with the username "Albert"
User.find({ "username" => "Albert" })
```

### Filtering results

```crystal
# Find all users from Argentina
User.find({ "country" => "Argentina" })

# Find all active users from Argentina
User.find({ "country" => "Argentina", { "status" => "active" })

# Find all active users from Argentina and Uruguay
User.find({ "status" => "active" }).combine({ "country" => ["Argentina", "Uruguay"] })

# Find all users from Argentina, except those with a suspended account.
User.find({ "country" => "Argentina").except({ "status" => "suspended" })

# Find all users both from Argentina and Uruguay
User.find({ "country" => "Argentina").union({ "country" => "Uruguay" })
```

Note that calling these methods results in new sets being created
on the fly. This is important so that you can perform further operations
before reading the items to the client.

For more information, see [SINTERSTORE](http://redis.io/commands/sinterstore),
[SDIFFSTORE](http://redis.io/commands/sdiffstore) and
[SUNIONSTORE](http://redis.io/commands/sunionstore).

Uniques
-------

Uniques are similar to indices except that there can only be one record per
entry. The canonical example of course would be the email of your user, e.g.

```crystal
class User < Ohm::Model
  attribute :email
  unique :email
end

u = User.create({ "email" => "foo@bar.com" })
u == User.with("email", "foo@bar.com")
# => true

User.create({ "email" => "foo@bar.com" })
# => raises Ohm::UniqueIndexViolation
```

[redis]: http://redis.io
[ohm]: http://github.com/soveran/ohm-crystal
[resp]: https://github.com/soveran/resp-crystal
