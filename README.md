Mongraph [mɔ̃ ˈɡrɑːf]
========

[![Build Status](https://api.travis-ci.org/pstaender/mongraph.png)](https://travis-ci.org/pstaender/mongraph)

Mongraph combines documentstorage database with graph-database relationships.

**Experimental. API may change.**

### Dependencies

#### Databases

* MongoDB (2+)
* Neo4j (1.8+)

#### Needs following modules to work with

* mongoose ORM <https://github.com/learnboost/mongoose> `npm install mongoose`
* Neo4j REST API client by thingdom <https://github.com/thingdom/node-neo4j> `npm install neo4j`

### Usage

```sh
  $ npm install mongraph
```

or clone repository to your prpject and install dependencies with npm:

```sh
  $ git clone git@github.com:pstaender/mongraph.git
  $ cd mongraph && npm install
```

### Example 

```coffeescript
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
```

produces the following output:

```
  Alice -> Bob
  Bob -> Charles
  Bob -> Zoe
  Charles -> Zoe
  Alice -> Bob -> Charles -> Zoe
  Alice -> Bob -> Zoe
  Shortest Path: Alice knows Zoe through Bob
```

This should demonstrate how to query graphdb and get as result mongodb documents. It exists a method Document::shortestPathTo(doc) for this need.

More examples in `test/tests.coffee` and `examples/`

### License

The MIT License (MIT) Copyright (c) 2012 Mark Cavage

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### TODO's

* shortestPath method (nice to have)
* caching of loaded nodes and documents
* deeper testing + better code coverage
