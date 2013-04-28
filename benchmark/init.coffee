Benchmark = require('benchmark')
# Suite     = Benchmark.Suite
# suite = new Benchmark.Suite

# mongoose
mongoose   = require('mongoose')
mongoose.connect("mongodb://localhost/testdb")
Person = mongoose.model "Person", value: Number

# "native"
mongoskin = require("mongoskin")
mongodb   = mongoskin.db("localhost:27017/testdb", {safe:false})

# neo4j
neo4j  = require('neo4j')
graph  = new neo4j.GraphDatabase('http://localhost:7474')

# mongraph
mongraph   = require '../src/mongraph'  
mongraph.init { neo4j: graph, mongoose: mongoose }
# Location is not with mongraph hooks
Location   = mongoose.model "Location", value: Number

randomInteger = (floor = 0, ceiling = 1) -> Math.round(Math.random()*(ceiling-floor))+floor

exports = module.exports = {mongraph,graph,mongodb,randomInteger,Benchmark,Person,Location}