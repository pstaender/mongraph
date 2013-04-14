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

Every document which is created in MongoDB will have a corresponding node in Neo4J:

```
  [{ _id: 51693565c977a40e28000002, _node_id: 1 }]                -> document
                            |
                            |
  ({ id: 1, _id: 51693565c977a40e28000002, collection: 'people'}) -> node
```

Each document has an extra attribute:

  * `_node_id` (id of the corresponding node)

Each node has extra attributes:

  * `_id` (id of the corresponding document)
  * `collection` (name of the collection of the corresponding document)

Each relationship will store informations about the start- and end-point-document and it's collection (timestamp is optional):

```
  (node#a) - { _from: "people:51693565c977a40e28000002", _to: "locations:51693565c977a40e28000001", _created_at: 1365849448 } - (node#b)
```

### What can it do?

To access the corresponding node:

```js
  // We have created/saved the document before
  console.log(document._node_id); // prints the id of the corresponding node
  document.getNode(function(err, node){
    console.log(node); // prints the node object
  });
```

To access the corresponding document:

```js
  console.log(node.data._id); // prints the id of the corresponding document
  console.log(node.data.collection); // prints the collection name of the corresponding document
  node.getDocument(function(err, document){
    console.log(document); // prints the document object
  });
```

You can create relationships between documents like you can do in Neo4j with nodes:

```js
  // create an outgoing relationship to another document
  // please remember that we have to work here always with callbacks...
  // that's why we are having the streamline placeholder here `_` (better to read)
  document.createRelationshipTo(otherDocument, _);
  // create an incoming relationship from another document
  document.createRelationshipFrom(otherDocument, _);
  // create a relationship between documents (bidirectional)
  document.createRelationshipBetween(otherDocument, _);
```

You can get and remove relationships from documents like you can do in Neo4j:

```js
  // get all documents which are pointing to this document with 'view'
  document.incomingRelationships('view', _);
  // get all documents that are connected with 'view' (bidirectional)
  document.allRelationships('view', _);
```

You can query the results with the MongoDB query:

```js
  // get all documents which are pointing to this document with 'view'
  // and the attribute title starts with an uppercase character
  document.incomingRelationships('view', { where: { title: /^[A-Z]/ } });
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
  * avoid loading all documents if we have a specific mongodb query (particular done already)
  * benchmark
  * more examples, documentation and better readme
  * refactor `processtools` and create seperate extensions for node, path and relationship (neo4j)
