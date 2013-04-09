// required modules
var mongoose  = require('mongoose')
  , neo4j     = require('neo4j')
  , mongraph  = require('../lib/mongraph')
  , graphdb   = new neo4j.GraphDatabase('http://localhost:7474')
  , mongodb   = mongoose.createConnection("mongodb://localhost/mongraph_example");

// apply mongraph functionalities
mongraph.init({
  neo4j: graphdb,
  mongodb: mongodb,
  mongoose: mongoose
});

// Define a schema with mongoose as usual
var Message = mongodb.model("Message", {
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
    


