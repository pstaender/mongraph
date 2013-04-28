{mongraph,graph,mongodb,randomInteger,Benchmark,Person,Location} = require './init'

suite = new Benchmark.Suite

suite.add "creating native mongodb documents", (deferred) ->
  mongodb.collection("people").insert value: Math.random(), (err, document) ->
    deferred.resolve()
, defer: true

suite.add "creating mongoose documents", (deferred) ->
  foo = new Person(value: Math.random())
  foo.save (err, document) ->
    deferred.resolve()
, defer: true

suite.add "creating neo4j nodes", (deferred) ->
  node = graph.createNode value: Math.random()
  node.save ->
    deferred.resolve()
, defer: true

suite.add "creating mongraph documents", (deferred) ->
  bar = new Location(value: Math.random())
  bar.save (err, document) ->
    deferred.resolve()
, defer: true

suite.on "cycle", (event) ->
  console.log "* "+String(event.target)

exports = module.exports = {suite}