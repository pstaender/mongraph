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

```js
  // required modules
  var mongoose  = require('mongoose')
    , neo4j     = require('neo4j')
    , mongraph  = require('../lib/mongraph')
    , graphdb   = new neo4j.GraphDatabase('http://localhost:7474');

  mongoose.connect("mongodb://localhost/mongraph_example");

  // apply mongraph functionalities
  mongraph.init({
    neo4j: graphdb,
    mongoose: mongoose
  });

  // Define a schema with mongoose as usual
  var Message = mongoose.model("Message", {
    name: String,
    content: String
  });

  // message a
  var monicaMessage = new Message({
    name: 'monica',
    content: 'hello graphdatabase world.\nregards\nmonica'
  });

  // message b
  var neoMessage = new Message({
    name: 'neo',
  });

  var print = console.log;

  // we have two documents
  print('-> monica');
  print('<- neo\n');

  monicaMessage.save(function(err) {
    // after Message is stored send message
    monicaMessage.createRelationshipTo(
      neoMessage,
      'sends',
      { sendWith: 'love' }, // define some attributes on the relationship (optional)
      function(err, relationship) {
        // relationship created / message sended
        if (!err)
          print('-> '+monicaMessage.name+' sended a message to neo');
      }
    );
  });

  setInterval(function(){
    // check for new messages
    neoMessage.incomingRelationships('sends',function(err, relationships){
      if ((relationships) && (relationships.length > 0)) {
        var message = relationships[0];
        print('<- neo received '+relationships.length+' message(s)');
        print('<- sended by '+message.from.name+' with '+message.data.sendWith+' ~'+((Math.round(new Date().getTime()/1000)) - message.data._created_at)+' secs ago');
        // display message
        print(String("\n"+message.from.content).split("\n").join("\n>> ")+"\n");
        // delete send relation from monica
        neoMessage.removeRelationshipsFrom(monicaMessage, 'sends', function() {
          print('<- neo read the message');
        });
        // mark as read
        neoMessage.createRelationshipTo(
          monicaMessage,
          'read',
          { readWith: 'care' }
        );
      } else {
        neoMessage.outgoingRelationships('read', function(err, readMessages) {
          var readWith = '';
          for (var i=0; i<readMessages.length; i++) {
            readWith += 'message#'+(i+1)+' read with '+readMessages[i].data.readWith;
          }
          print('<- 0 new messages, '+readMessages.length+' read message(s), '+readWith);
          // done
          process.exit(0);
        });
      }
      
    });
  }, 500);
```

produces the following output:

```
  -> monica
  <- neo

  -> monica sended a message to neo
  <- neo received 1 message(s)
  <- sended by monica with love ~1 secs ago

  >> hello graphdatabase world.
  >> regards
  >> monica

  <- neo read the message
  <- 0 new messages, 1 read message(s), message#1 read with care
```

More examples in `test/tests.coffee`

### License

The MIT License (MIT) Copyright (c) 2012 Mark Cavage

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### TODO's

* shortestPath method (nice to have)
* caching of loaded nodes and documents
* deeper testing + better code coverage
