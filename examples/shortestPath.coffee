# Load required modules
mongoose = require("mongoose")
mongoose.connect("mongodb://localhost/mongraph_example")
neo4j = require("neo4j")
mongraph = require("../src/mongraph")
graphdb = new neo4j.GraphDatabase("http://localhost:7474")
print = console.log

# Init mongraph
#
# Hint: Always init mongraph **before** defining Schemas
# Otherwise the mograph mongoose-plugin will not be affected:
#
# * no storage of the Node id in the Document
# * no automatic deletion of relationships and corresponding nodes in graphdb
# 
# Alternatively you can apply the plugin by yourself:
# 
# `mongoose.plugin require('./node_modules/mongraph/src/mongraphMongoosePlugin')`

mongraph.init
  neo4j: graphdb
  mongoose: mongoose

# Define model
Person = mongoose.model("Person", name: String)

# Example data
alice   = new Person(name: "Alice")
bob     = new Person(name: "Bob")
charles = new Person(name: "Charles")
zoe     = new Person(name: "Zoe")

# The following shall demonstrate how to work with Documents and it's corresponding Nodes
# Best practice would be to manage this with joins or streamlines instead of seperate callbacks
# But here we go through callback hell ;)
alice.save -> bob.save -> charles.save -> zoe.save ->
  # stored
  alice.getNode (err, aliceNode) -> bob.getNode (err, bobNode) -> charles.getNode (err, charlesNode) -> zoe.getNode (err, zoeNode) ->
    alice.createRelationshipTo bob, 'knows', (err, relation) -> alice.getNode (err, node) ->
      print "#{alice.name} -> #{bob.name}"
      bob.createRelationshipTo charles, 'knows', (err, relation) -> bob.getNode (err, node) ->
        print "#{bob.name} -> #{charles.name}"
        bob.createRelationshipTo zoe, 'knows', (err, relation) ->
          print "#{bob.name} -> #{zoe.name}"
          charles.createRelationshipTo zoe, 'knows', (err, relation) ->
            print "#{charles.name} -> #{zoe.name}"
            print "#{alice.name} -> #{bob.name} -> #{charles.name} -> #{zoe.name}"
            print "#{alice.name} -> #{bob.name} -> #{zoe.name}"
            query = """
              START a = node(#{aliceNode.id}), b = node(#{zoeNode.id}) 
              MATCH p = shortestPath( a-[*..15]->b )
              RETURN p;
            """
            alice.queryGraph query, (err, docs) ->
              print "\nShortest path is #{docs.length-1} nodes long: #{docs[0].name} knows #{docs[2].name} through #{docs[1].name}"