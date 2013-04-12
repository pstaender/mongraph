# required modules
mongoose = require("mongoose")
mongoose.connect("mongodb://localhost/mongraph_example")
neo4j = require("neo4j")
mongraph = require("../src/mongraph")
graphdb = new neo4j.GraphDatabase("http://localhost:7474")
process = require("../src/processtools")
print = console.log

# init
mongraph.init
  neo4j: graphdb
  mongoose: mongoose

# define mode
Person = mongoose.model("Person", name: String)

# example data
alice   = new Person(name: "Alice")
bob     = new Person(name: "Bob")
charles = new Person(name: "Charles")
zoe     = new Person(name: "Zoe")

alice.save -> bob.save -> charles.save -> zoe.save ->
  # stored
  alice.createRelationshipTo bob, 'knows', (err, relation) ->
    print "#{alice.name} -> #{bob.name}"
    aliceNodeID = relation.start.id
    bob.createRelationshipTo charles, 'knows', (err, relation) ->
      bobNodeID = relation.start.od
      charlesNodeID = relation.end.id
      print "#{bob.name} -> #{charles.name}"
      bob.createRelationshipTo zoe, 'knows', (err, relation) ->
        print "#{bob.name} -> #{zoe.name}"
        charles.createRelationshipTo zoe, 'knows', (err, relation) ->
          print "#{charles.name} -> #{zoe.name}"
          print "#{alice.name} -> #{bob.name} -> #{charles.name} -> #{zoe.name}"
          print "#{alice.name} -> #{bob.name} -> #{zoe.name}"
          zoeNodeID = relation.end.id
          query = """
            START a = node(#{aliceNodeID}), b = node(#{zoeNodeID}) 
            MATCH p = shortestPath( a-[*..15]->b )
            RETURN p;
          """
          alice.queryGraph query, (err, docs) ->
            print "Shortest Path: #{docs[0].name} knows #{docs[2].name} through #{docs[1].name}"

