{mongraph,graph,mongodb,randomInteger,Benchmark,Person,Location} = require './init'

suite = new Benchmark.Suite

suite.add 'selecting node', (deferred) ->
  # skip  = randomNumber(10)
  # limit = randomNumber(10)
  # RETURN t SKIP #{skip} LIMIT #{limit}
  graph.query "START t=node(*) LIMIT 1 RETURN t;", (err, found) ->
    deferred.resolve()
, defer: true

suite.add 'selecting native document', (deferred) ->
  mongodb.collection("people").findOne {}, (err, found) ->
    deferred.resolve()
, defer: true

suite.add 'selecting mongoosse document', (deferred) ->
  Person.findOne {}, (err, found) ->
    deferred.resolve()
, defer: true

suite.add 'selecting document with corresponding node', (deferred) ->
  Location.findOne {}, (err, found) ->
    found.getNode ->
      deferred.resolve()
, defer: true

suite.on "cycle", (event) ->
  console.log "* "+String(event.target)

exports = module.exports = {suite}