{mongraph,graph,mongodb,randomInteger,Benchmark,Person,Location} = require './init'

suite = new Benchmark.Suite

suite.add "deleting native mongodb documents", (deferred) ->
  mongodb.collection("people").insert value: Math.random(), (err, document) ->
    mongodb.collection("people").removeById document._id, (err) ->
      deferred.resolve()
, defer: true

suite.add "deleting mongoose documents", (deferred) ->
  foo = new Person(value: Math.random())
  foo.save (err, document) -> foo.remove (err) ->
    deferred.resolve()
, defer: true

suite.add "deleting neo4j nodes", (deferred) ->
  node = graph.createNode value: Math.random()
  node.save -> node.delete (err) ->
    deferred.resolve()
, defer: true

suite.add "deleting mongraph documents", (deferred) ->
  bar = new Location(value: Math.random())
  bar.save (err, document) -> bar.remove (err) ->
    deferred.resolve()
, defer: true

suite.on "cycle", (event) ->
  console.log "* "+String(event.target)

exports = module.exports = {suite}