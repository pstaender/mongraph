# TODO: make tests mor independent: beforeEach -> delete all relations

# source map support for coffee-script ~1.6.1
require('source-map-support').install()

expect     = require('expect.js')
mongoose   = require('mongoose')
neo4j      = require('neo4j')
mongraph   = require('../src/mongraph')
cleanupDBs = true # remove all test-created documents, nodes + relationship
Join       = require('join')

describe "Mongraph", ->

  # schemas and data objects
  Person = Location = alice = bob = charles = dave = elon = zoe = bar = pub = null
  # handler for connections
  mongo  = graph = null
  # regex for validating objectid
  regexID = /^[a-f0-9]{24}$/

  before (done) ->

    # Establish connections to mongodb + neo4j
    graph = new neo4j.GraphDatabase('http://localhost:7474')
    mongoose.connect("mongodb://localhost/mongraph_test")

    # initialize mongraph
    mongraph.init {
      neo4j: graph
      mongoose: mongoose
    }
    
    # Define model
    schema = new mongoose.Schema(name: String)

    # is used for checking that we are working with the mongoose model and not with native mongodb objects
    schema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name

    Person   = mongoose.model "Person", schema
    Location = mongoose.model "Location", mongoose.Schema(name: String, lon: Number, lat: Number)

    alice   = new Person(name: "alice")
    bob     = new Person(name: "bob")
    charles = new Person(name: "charles")
    zoe     = new Person(name: "zoe")

    bar     = new Location(name: "Bar", lon: 52.51, lat: 13.49)
    pub     = new Location(name: "Pub", lon: 40, lat: 10)

    createExampleDocuments = (cb) ->
      # create + store documents
      alice.save -> bob.save -> charles.save -> zoe.save ->
        bar.save -> pub.save ->
          cb()

    if cleanupDBs
      # remove all records
      Person.remove -> Location.remove -> createExampleDocuments ->
        done()
    else
      done()

  beforeEach (done) ->
    # remove all relationships
    alice.removeRelationships '*', -> bob.removeRelationships '*', -> zoe.removeRelationships '*', ->
      bar.removeRelationships '*', -> pub.removeRelationships '*', ->
        # **knows**
        # alice -> bob -> charles -> zoe
        # bob -> zoe
        # alice <- zoe
        #
        # **visits*
        # alice -> bar
        # alice -> pub
        alice.createRelationshipTo bob, 'knows', { since: 'years' }, ->
          alice.createRelationshipFrom zoe, 'knows', { since: 'months' }, ->
            bob.createRelationshipTo charles, 'knows', ->
              charles.createRelationshipTo zoe, 'knows', ->
                bob.createRelationshipTo zoe, 'knows', ->
                  alice.createRelationshipTo bar, 'visits', ->
                    alice.createRelationshipTo pub, 'visits', ->
                      done()
  after (done) ->
    return done() unless cleanupDBs
    # Remove all persons and locations with documents + nodes
    join = Join.create()
    for record in [ alice, bob, charles, dave, elon, zoe, bar, pub ]
      do (record) ->
        callback = join.add()
        record.remove callback
    join.when (a, b) ->
      done()

  describe 'processtools', ->

    describe '#getObjectIDAsString()', ->
    
      it 'expect to extract the id from various kind of argument types', ->
        expect(mongraph.processtools.getObjectIDAsString(alice)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(alice._id)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(String(alice._id))).to.match(regexID)
  
  describe 'mongraph', ->

    describe '#init()', ->

      it 'expect that we have the all needed records in mongodb', (done) ->
        persons = []
        Person.count (err, count) ->
          expect(count).to.be.equal 4
          Location.count (err, count) ->
            expect(count).to.be.equal 2
            done()

  describe 'mongoose::Document', ->

    describe '#getNode()', ->

      it 'expect not to get a corresponding node for an unstored document in graphdb', (done) ->
        elon = Person(name: "elon")
        expect(elon._node_id).not.to.be.above 0
        elon.getNode (err, found) ->
          expect(err).not.to.be null
          expect(found).to.be null
          done()

      it 'expect to find always the same corresponding node to a stored document', (done) ->
        elon = Person(name: "elon")
        elon.save (err, elon) ->
          expect(err).to.be null
          nodeID = elon._node_id
          expect(nodeID).to.be.above 0
          elon.getNode (err, node) ->
            expect(err).to.be null
            expect(node.id).to.be.equal node.id
            done()

    describe '#createRelationshipTo()', ->

      it 'expect to create an outgoing relationship from this document to another document', (done) ->
        alice.createRelationshipTo bob, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship.start.data._id).to.be.equal (String) alice._id
          expect(relationship.end.data._id).to.be.equal (String) bob._id
          expect(relationship._data.type).to.be.equal 'knows'
          alice.createRelationshipTo zoe, 'knows', { since: 'years' }, (err, relationship) ->
            expect(relationship.start.data._id).to.be.equal (String) alice._id
            expect(relationship.end.data._id).to.be.equal (String) zoe._id
            expect(relationship._data.type).to.be.equal 'knows'
            done()

    describe '#createRelationshipFrom()', ->

      it 'expect to create an incoming relationship from another document to this document' , (done) ->
        bob.createRelationshipFrom zoe, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship.start.data._id).to.be.equal (String) zoe._id
          expect(relationship.end.data._id).to.be.equal (String) bob._id
          done()

    describe '#createRelationshipBetween()', ->

      it 'expect to create a relationship between two documents (bidirectional)', (done) ->
        alice.createRelationshipBetween bob, 'follows', {}, (err, relationships) ->
          expect(err).to.be null
          expect(relationships).have.length 2

          _ids = {}
          for relation in relationships
            _ids[relation.start.data._id] = true
          expect(_ids).to.only.have.keys( String(alice._id), String(bob._id) )

          done()

          # TODO: fix loading relationships[0].start.document

          # names = {}
          # for relation in relationships
          #   names[relation.start.document.name] = true
          # expect(names).to.only.have.keys( 'alice', 'bob' )
          # TODO: we should also test, that we get the correct relationships via incoming + outgoing
          # maybe a cypher query could be a good proof here
          # done()

    describe '#removeRelationshipsTo', ->

      it 'expect to remove outgoing relationships to a document', (done) ->
        # zoe gets to follow bob
        zoe.createRelationshipTo bob, 'follows', (err, relationship) ->
          expect(err).to.be null
          # zoe follows bob
          zoe.outgoingRelationships 'follows', (err, follows) ->
            expect(err).to.be null
            expect(follows).to.have.length 1
            expect(follows[0].to.name).to.be.equal 'bob'
            # zoe stops all 'follow' activities
            zoe.removeRelationshipsTo bob, 'follows', (err, a) ->
              expect(err).to.be null
              zoe.outgoingRelationships 'follows', (err, follows) ->
                expect(err).to.be null
                expect(follows).to.have.length 0
                done()

    describe '#removeRelationshipsFrom', ->

      it 'expects to remove incoming relationships from a document', (done) ->
        alice.incomingRelationships 'knows', (err, relationships) ->
          countBefore = relationships.length
          expect(relationships.length).to.be.equal 1
          expect(relationships[0].from.name).to.be.equal 'zoe'
          alice.removeRelationshipsFrom zoe, 'knows', (err, query, options) ->
            expect(err).to.be null
            alice.incomingRelationships 'knows',(err, relationships) ->
              expect(relationships.length).to.be.equal 0
              done()

    describe '#removeRelationshipsBetween', ->

      it 'expects to remove incoming and outgoing relationships between two documents', (done) ->
        # alice <-knows-> zoe
        alice.removeRelationships 'knows', -> zoe.removeRelationships 'knows', ->
          alice.createRelationshipTo zoe, 'knows', -> zoe.createRelationshipTo alice, 'knows', (err) ->
            alice.incomingRelationships 'knows', (err, relationships) ->
              aliceCountBefore = relationships.length
              zoe.incomingRelationships 'knows', (err, relationships) ->
                zoeCountBefore = relationships.length
                expect(relationships[0].from.name).to.be.equal 'alice'
                zoe.removeRelationshipsBetween alice, 'knows', (err) ->
                  expect(err).to.be null
                  alice.incomingRelationships 'knows', (err, aliceRelationships) ->
                    expect(aliceRelationships.length).to.be.below aliceCountBefore
                    zoe.incomingRelationships 'knows', (err, zoeRelationships) ->
                      expect(zoeRelationships.length).to.be.below zoeCountBefore
                      done()

    describe '#removeRelationships', ->

      it 'expects to remove all incoming and outgoing relationships', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships.length).to.be.above 0
          alice.removeRelationships 'knows', (err) ->
            expect(err).to.be null
            alice.allRelationships 'knows', (err, relationships) ->
              expect(relationships).to.have.length 0
              done()

      it 'expect to remove all relationship of a specific type', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships?.length).be.above 0
          alice.removeRelationships 'knows', (err, relationships) ->
            expect(relationships).to.have.length 0
            done()

    describe '#allRelationships()', ->

      it 'expect to get incoming and outgoing relationships as relationship object', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].data.since).to.be.equal 'years'
          done()

      it 'expect to get incoming and outgoing relationships as counted number', (done) ->
        alice.allRelationships 'knows', { countRelationships: true }, (err, count) ->
          expect(count).to.be.equal 2
          done()

      it 'expect to get all related documents attached to relationships', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].from).to.be.an 'object'
          expect(relationships[0].to).to.be.an 'object'
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'alice', 'bob' )
          done()

      it 'expect to get outgoing relationships+documents from a specific collection', (done) ->
        alice.outgoingRelationships '*', { collection: 'locations' }, (err, relationships) ->
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'Bar', 'Pub' )
          expect(relationships).to.have.length 2
          expect(err).to.be null
          done()

      it 'expect to get incoming relationships+documents with a condition', (done) ->
        alice.outgoingRelationships '*', { where: { name: /^[A-Z]/ } }, (err, relationships) ->
          expect(relationships).to.have.length 2
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'Bar', 'Pub' )
          done()

    describe '#incomingRelationships()', ->

      it 'expect to get only incoming relationships', (done) ->
        alice.incomingRelationships 'knows', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 1
          expect(result[0].data.since).be.equal 'months'
          done()

      it 'expect to get incoming relationships+documents from a specific collection', (done) ->
        alice.incomingRelationships '*', { collection: 'people' }, (err, relationships) ->
          expect(relationships).to.have.length 1
          expect(relationships[0].from.name).to.be 'zoe'
          done()

    describe '#outgoingRelationships()', ->

      it 'expect to get only outgoing relationshipss', (done) ->
        alice.outgoingRelationships 'visits', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 2
          done()

    describe '#removeNode()', ->

      it 'expect to remove a node including all incoming and outgoing relationships', (done) ->
        dave = new Person(name: "dave")
        dave.save (err, dave) -> dave.getNode (err, node) ->
          nodeId = node.id
          expect(nodeId).to.be.above 0
          dave.createRelationshipTo zoe, 'likes', -> zoe.createRelationshipTo dave, 'likes', -> dave.allRelationships 'likes', (err, likes) ->
            expect(likes).to.have.length 2
            dave.removeNode (err, result) ->
              expect(err).to.be null
              graph.getNodeById nodeId, (err, found) ->
                expect(found).to.be undefined
                dave.allRelationships 'likes', (err, likes) ->
                  expect(likes).to.be null
                  done()

    describe '#shortestPath()', ->

      it 'expect to get the shortest path between two documents', (done) ->
        alice.shortestPathTo zoe, 'knows', (err, path) ->
          expect(path).to.be.an 'object'
          expect(err).to.be null
          expectedPath = [ alice._id, bob._id, zoe._id ]
          for node, i in path
            expect(String(node._id)).be.equal String(expectedPath[i])
          done()
      
      it 'expect to get a mongoose document instead of a native mongodb document', (done) ->
        alice.shortestPathTo zoe, 'knows', (err, path) ->
          expect(path).to.have.length 3
          expect(path[0].fullname).to.be.equal 'alice a.'
          done()

      it 'expect to get a mongoose document with conditions', (done) ->
        alice.shortestPathTo zoe, 'knows', { where: { name: /o/ } }, (err, path) ->
          bob = path[0]
          zoe = path[1]
          expect(bob.name).to.be.equal 'bob'
          expect(zoe.name).to.be.equal 'zoe'
          expect(path).to.have.length 2
          done()


  describe 'Neo4j::Node', ->

    describe '#getCollectionName()', ->

      it 'expect to get the collection name from a node', (done) ->
        # create also a new node
        emptyNode = graph.createNode()
        alice.getNode (err, node) ->
          expect(node.getCollectionName()).to.be.equal('people')
          expect(emptyNode.getCollectionName()).to.be(undefined)
          done()

    describe '#getMongoId()', ->

      it 'expect to get the id of the corresponding document from a node', (done) ->
        alice.getNode (err, node) ->
          expect(node.getMongoId()).to.be.equal (String) alice._id
          done()

    describe '#getDocument()', ->

      it 'expect to get equivalent document from a node', (done) ->
        alice.getNode (err, node) ->
          expect(node).to.be.an 'object'
          node.getDocument (err, doc) ->
            expect(doc).to.be.an 'object'
            expect(String(doc._id)).to.be.equal (String) alice._id
            done()

      
    
