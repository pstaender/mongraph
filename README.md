Mongraph [mɔ̃ ˈɡrɑːf]
========

[![Build Status](https://api.travis-ci.org/pstaender/mongraph.png)](https://travis-ci.org/pstaender/mongraph)

Mongraph combines documentstorage database with graph-database relationships by creating a corresponding node for each document.

**Experimental. API may change.**
**Currently it's only tested against Neo4j v2.0 and Neo4j v2.1**

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
             [{ _id: 5169…2, _node_id: 1 }]                  -> document in MongoDB
                           / \
                            |
                            |
                           \ /
  ({ id: 1, data: { _id: 5169…2, _collection: 'people'} })   -> node in Neo4j
```

Each document has an extra attribute:

  * `_node_id` (id of the corresponding node)

Each node has extra attributes:

  * `_id` (id of the corresponding document)
  * `_collection` (name of the collection of the corresponding document)

Each relationship will store informations about the start- and end-point-document and it's collection:

```
  (node#a) - { _from: "people:516…2", _to: "locations:516…3" … } - (node#b)
```

### What can it do?

To access the corresponding node:

```js
  // We can work with relationship after the document is stored in MongoDB
  document = new Document({ title: 'Document Title'});
  document.save(function(err, savedDocument){
    savedDocument.log(savedDocument._node_id); // prints the id of the corresponding node
    savedDocument.getNode(function(err, correspondingNode){
      console.log(correspondingNode); // prints the node
    });
  });
```

To access the corresponding document:

```js
  console.log(node.data._id); // prints the id of the corresponding document
  console.log(node.data._collection); // prints the collection name of the corresponding 
  node.getDocument(function(err, correspondingDocument){
    console.log(correspondingDocument); // prints the document
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
  // get all documents which are pointing via 'view'
  document.incomingRelationships('view', _);
  // get all documents that are connected with 'view' (bidirectional)
  document.allRelationships('view', _);
  // same between documents
  document.allRelationshipsBetween(otherDocument, 'view', _);
  document.incomingRelationshipsFrom(otherDocument, 'view', _);
  document.outgoingRelationshipsTo(otherDocument, 'view', _);
```

You can filter the documents (mongodb) **and** the relationships (neo4j):

```js
  // get all similar documents where title starts with an uppercase
  // and that are connected with the attribute `scientific report`
  document.incomingRelationships(
    'similar',
    {
      where: {
        document: {
          // we can query with the familiar mongodb query
          title: /^[A-Z]/
        },
        // queries on graph are strings, because they are passed trough the cypher query directly for now
        // here: relationship objects are accessible as `r` by default, start node as `a` and end node (if is queried) as `b` 
        relationship: "r.category! = 'scientific report'"
      }
    }, _
  );
```

You can also make your custom graph queries:

```js
  document.queryGraph(
    "START a = node(1), b = node(2) MATCH path = shortestPath( a-[*..5]->b ) RETURN path;", 
    { processPart: 'path' },
    function(err, path, options) { … }
  );
```

To get more informations about made queries (and finally used options) inspect the passed through options argument (`debug: true` enables logging of queries):

```js
  document.incomingRelationships(
    'similar', { debug: true }, function(err, found, options) {
      // prints out finally used options and - if set to `true` - additional debug informations
      console.log(options.debug);
      // { cypher: [ "START … MATCH …" , …] … }}
    }
  );
```

### Store in mongodb and neo4j simultaneously

Since v0.1.15 you can store defined properties from mongodb documents in the corresponding nodes in neo4j. It might be a matter of opinion whether it's a good idea to store data redundant in two database system, anyway mongraph provides a tool to automate this process.

You need to provide the requested fields in your mongoose schemas with a `graph = true` option. Please note: If the property includes the `index = true` option (used in mongoose to index property in mongodb) this field will be also indexed in the graphdatabase.

Since neo4j nodes store only non nested objects, your object will be flatten; e.g.:

```js

  data = {
    property: {
      subproperty: true
    }
  };
  // will become
  // data['property.subproperty'] = true
```

```js
messageSchema = new mongoose.Schema({
  text: {
    title: {
      type: String,
      graph: true // field / value will be stored in neo4j
      index: true, // will be an indexed in neo4j as well
    },
    content: String
  },
  from: {
    type: String,
    graph: true  // field / value will be stored in neo4j, but not be indexed
  }
});
``` 

### Your documents + nodes on neo4j

By default all corresponding nodes are created indexed with the collection-name and the _id, so that you can easily access them through neo4j, e.g.:

```
  http://localhost:7474/db/data/index/node/people/_id/5178fc1f6955993a25004711
``` 

### Requirements

#### Databases:

  * MongoDB (~2)
  * Neo4j (~2)

#### NPM modules:

  * mongoose ORM <https://github.com/learnboost/mongoose> `npm install mongoose`
  * Neo4j REST API client by thingdom <https://github.com/thingdom/node-neo4j> `npm install neo4j`

### Examples and Tests

You'll find examples in `test/tests.coffee` and `examples/`.

### Benchmarks

`npm run benchmark` should output s.th. like:

```
### CREATING RECORDS

* creating native mongodb documents x 964 ops/sec ±3.23% (68 runs sampled)
* creating mongoose documents x 521 ops/sec ±1.25% (81 runs sampled)
* creating neo4j nodes x 302 ops/sec ±13.87% (68 runs sampled)
* creating mongraph documents x 132 ops/sec ±9.01% (68 runs sampled)

**Fastest** is creating native mongodb documents

**Slowest** is creating mongraph documents


### FINDING RECORDS

* selecting node x 279 ops/sec ±1.40% (84 runs sampled)
* selecting native document x 627 ops/sec ±0.98% (80 runs sampled)
* selecting mongoosse document x 574 ops/sec ±1.30% (78 runs sampled)
* selecting document with corresponding node x 295 ops/sec ±9.45% (63 runs sampled)

**Fastest** is selecting native document

**Slowest** is selecting document with corresponding node
```

### Changelogs

#### 0.1.14

  * **API Change:** the collection of the corresponding document will be stored from now on as `_collection` instead of `collection` in each node. e.g.: `node -> { data: { _id: 5ef6…, _collection: 'people' } }`, reason: continious name conventions in node-, document-, relationship- + path objects

#### 0.2.0

  * removed legacy node modules (source mapping for instance)
  * ignoring neo4j v<2
  * tested sucessfully against mongodb 2.6.x and Neo4J v2.0.x and v2.1.x

### Tests

Tested successfully against mongodb 2.6.x and Neo4J v2.0.x and v2.1.x.
Not ready for Neo4j v2.2 since the [neo4j module](https://github.com/thingdom/node-neo4j) for the latest Neo4j version is still under development.
Older Neo4j version than 2.x are not supported anymore.

### License

See [License file](https://github.com/pstaender/mongraph/blob/master/LICENSE).

### Contributors

  * [Marian C Moldovan](https://github.com/beeva-marianmoldovan)
  * [Robert Klep](https://github.com/robertklep)
  * [Joaquin Navarro](https://github.com/beeva-joaquinnavarro)

### Known issues and upcoming features

  * process tools should avoid loading all documents on specific mongodb queries -> more effective queries
  * using document `_id` as primary key in neo4j as well (in other words, drop support for `node_id` / `id`)
  * using labels-feature for nodes (neo4j 2.0+) instead of `_collection` property
  * dump and restore of relationships
  * real-life benchmarks
