# Innertube

Innertube is a thread-safe, re-entrant resource pool, extracted from
the [Riak Ruby Client](/basho/riak-ruby-client), where it was used to
pool connections to [Riak](/basho/riak). It is free to use and modify,
licensed under the Apache 2.0 License.

## Example

```ruby
# -------------------------------------------------------
# Basics
# -------------------------------------------------------

# Create a pool with open/close callables
pool = Innertube::Pool.new(proc { Connection.new },
                           proc {|c| c.disconnect })

# Optionally, fill the pool with existing resources
pool.fill([conn1, conn2, conn3])

# Grab a connection from the pool, returns the same value
# as the block
pool.take {|conn| conn.ping } # => true

# Raise the BadResource exception if the resource is no
# longer good
pool.take do |conn|
  raise Innertube::Pool::BadResource unless conn.connected?
  conn.ping
end

# Innertube helps your code be re-entrant! Take more resources
# while you have one checked out.
pool.take do |conn|
  conn.stream_tweets do |tweet|
    pool.take {|conn2| conn2.increment :tweets }
  end
end

# -------------------------------------------------------
# Iterations: These are slow because they have guarantees
# about visiting all current elements of the pool.
# -------------------------------------------------------

# Do something with every connection in the pool
pool.each {|conn| puts conn.get_stats }

# Expunge some expired connections from the pool
pool.delete_if {|conn| conn.idle_time > 5 }
```

## Credits

The pool was originally implemented by [Kyle Kingsbury](/aphyr) and
extracted by [Sean Cribbs](/seancribbs), when bugged about it by
[Pat Allan](/freelancing-god) at
[EuRuKo 2012](http://www.euruko2012.org/).
