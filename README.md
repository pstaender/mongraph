Mongraph [mɔ̃ ˈɡrɑːf]
========

[![Build Status](https://api.travis-ci.org/pstaender/mongraph.png)](https://travis-ci.org/pstaender/mongraph)

Mongraph combines documentstorage database with graph-database relationships by creating a corresponding node for each document.

**Experimental. API may change.**

### Installation

```sh
  $ npm install mongraph
```

or clone the repository to your project and install dependencies with npm:

```sh
  $ git clone git@github.com:pstaender/mongraph.git
  $ cd mongraph && npm install
```

### What's it good for?

MongoDB is great for a lot of things but a bit weak at relationships. However Neo4j is very powerful at this point but not the best solution for document storage. So why not using the best of both worlds?

### What does it take?

Every document which is created in MongoDB will have a corresponding node in Neo4j:

```
             [{ _id: 5169…2, _node_id: 1 }]                 -> document in MongoDB
                           / \
                            |
                            |
                           \ /
  ({ id: 1, data: { _id: 5169…2, collection: 'people'} })   -> node in Neo4j
```

Each document has an extra attribute:

  * `_node_id` (id of the corresponding node)

Each node has extra attributes:

  * `_id` (id of the corresponding document)
  * `collection` (name of the collection of the corresponding document)

Each relationship will store informations about the start- and end-point-document and it's collection (timestamp is optional):

```
  (node#a) - { _from: "people:516…2", _to: "locations:516…3", _created_at: 1365849448 } - (node#b)
```

### What can it do?

To access the corresponding node:

```js
  // We can work with relationship after the document is stored in MongoDB
  document = new Document({ title: 'Document Title'});
  document.save(function(err, savedDocument){
    savedDocument.log(savedDocument._node_id); // prints the id of the corresponding node
    savedDocument.getNode(function(err, correspondingNode){
      console.log(correspondingNode); // prints the node object
    });
  });
```

To access the corresponding document:

```js
  console.log(node.data._id); // prints the id of the corresponding document
  console.log(node.data.collection); // prints the collection name of the corresponding 
  node.getDocument(function(err, correspondingDocument){
    console.log(correspondingDocument); // prints the document object
  });
```

You can create relationships between documents like you can do in Neo4j with nodes:

```js
  // create an outgoing relationship to another document
  // please remember that we have to work here always with callbacks...
  // that's why we are having the streamline placeholder here `_` (better to read)
  document.createRelationshipTo(
    otherDocument, 'similar', { category: 'article' }, _
  );
  // create an incoming relationship from another document
  document.createRelationshipFrom(
    otherDocument, 'similar', { category: 'article' }, _
  );
  // create a relationship between documents (bidirectional)
  document.createRelationshipBetween(
    otherDocument, 'similar', { category: 'article'},  _
  );
```

You can get and remove relationships from documents like you can do in Neo4j:

```js
  // get all documents which are pointing to this document with 'view'
  document.incomingRelationships('similar', _);
  // get all documents that are connected with 'view' (bidirectional)
  document.allRelationships('similar', _);
```

You can query the documents (mongodb) **and** the relationships (neo4j):

```js
  // get all similar documents where title starts with an uppercase
  // and that are connected with the attribute `scientific report`
  document.incomingRelationships(
    'similar',
    {
      where: {
        document: {
          // we can query here with the familiar mongodb syntax
          title: /^[A-Z]/
        },
        // this query is a simple string, because it's passed directly to the cypher query for now
        relationship: "relationship.category! = 'scientific report'"
      }
    }, _
  );
```

To get more informations about queries (and finally used options) inspect the passed through options argument (`debug: true` causes that made queries are attached to `options` as well):

```js
  document.incomingRelationships(
    'similar', { debug: true }, function(err, found, options) {
      // prints out finally used options and - if set to `true` - additional debug informations
      console.log(options);
    }
  );
```

### Works together with

#### following databases

* MongoDB (~2)
* Neo4j (~1.8)

#### following npm modules

* mongoose ORM <https://github.com/learnboost/mongoose> `npm install mongoose`
* Neo4j REST API client by thingdom <https://github.com/thingdom/node-neo4j> `npm install neo4j`

### Examples and Tests

You'll find examples in `test/tests.coffee` and `examples/`.

### License

The MIT License (MIT) Copyright (c) 2013 Philipp Staender

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### TODO's

  * caching of loaded Nodes and Documents
  * avoid loading all documents if we have a specific mongodb query
  * benchmarks
  * more examples, documentation and better readme
