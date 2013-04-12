# TODO: make tests mor independent: beforeEach -> delete all relations

expect        = require('expect.js')
mongoose      = require('mongoose')
neo4j         = require('neo4j')
mongraph      = require('../src/mongraph')

describe "Mongraph", ->

  # schemas and data objects
  Person = alice = bob = charles = zoe = null
  # handler for connections
  mongo  = graph = null
  # regex for validating objectid
  regexID = /^[a-f0-9]{24}$/

  before (done) ->

    # Work with seperate connections for each testsuite run
    # Is paticular needed for `mocha -w`
    # -> https://github.com/LearnBoost/mongoose/issues/1043
    # -> https://github.com/LearnBoost/mongoose/issues/1251
    mongoose.connection.close()
    # Establish connections to mongodb + neo4j
    graph = new neo4j.GraphDatabase('http://localhost:7474')
    mongoose.connect("mongodb://localhost/mongraph_test")

    mongraph.init {
      neo4j: graph
      mongoose: mongoose
    }
    
    # Define model
    schema = new mongoose.Schema(name: String)
    
    # Used for checking that we are working with the mongoose model and not with native mongodb objects
    schema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name

    Person = mongoose.model "Person", schema

    # Ensure that we'll always get mongoose created Documents
    # Optional, but strongly recommend to do it
    mongraph.registerModels(mongoose)

    alice   = new Person(name: "alice")
    bob     = new Person(name: "bob")
    charles = new Person(name: "charles")
    zoe     = new Person(name: "zoe")

    # remove all previous persons
    Person.collection.remove (removeCollectionErr) ->
      # define example schema for person
      alice.save (aliceSavingErr) -> bob.save (bobSavingErr) -> charles.save (charlesSavingErr) -> zoe.save (zoeSavingErr) ->
        done(aliceSavingErr or bobSavingErr or zoeSavingErr or charlesSavingErr or removeCollectionErr)

  describe 'processtools', ->

    describe '#getObjectIDAsString()', ->
    
      it 'expect to extract the id from various kind of argument types', ->
        expect(mongraph.processtools.getObjectIDAsString(alice)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(alice._id)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(String(alice._id))).to.match(regexID)
  
  describe 'mongraph', ->

    describe '#init()', ->

      it 'expect that we have 2 persons we created available in mongodb', (done) ->
        persons = []
        Person.findById alice._id, (err, pers1) -> Person.findById bob._id, (err, pers2) ->
          persons.push(pers1) if pers1 and not err
          persons.push(pers2) if pers2 and not err
          expect(persons).to.have.length(2)
          done()

  describe 'mongoose::Document', ->

    describe '#findEquivalentNode()', ->

      it 'expect not to find an equivalent node for any person in graphdb', (done) ->
        for person, i in [ alice, bob ]
          do (i, person) ->          
            person.findEquivalentNode (err, found) ->
              expect(err).to.be(null)
              expect(found).to.be(undefined)
              done() if i is 1

    describe '#findOrCreateEquivalentNode()', ->

      it 'expect to find or create an equivalent node for each person', (done) ->
        for person, i in [ alice, bob ]
          do (i, person) ->
            person.findOrCreateEquivalentNode (err, node) ->
              expect(err).to.be(undefined)
              expect(node).to.be.an('object')
              expect(node.data._id).to.be.equal (String) person._id
              done() if i is 1

    describe '#findOrCreateEquivalentNode()', ->

      it 'expect to find a distinct node to each record', (done) ->
        previousNodeId = null
        for i in [ 0..1 ]
          do (i) ->
            alice.findOrCreateEquivalentNode (err, node) ->
              expect(node.data._id).to.be.equal (String) alice._id
              previousNodeId ?= node.id
              if i is 1
                # done
                expect(node.id).to.be.equal(previousNodeId)
                done() if i is 1

    describe '#createRelationshipTo()', ->

      it 'expect to create a relationship: alice knows bob', (done) ->
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

      it 'expect to create a relationship the other way round: zoe knows bob, but bob doesn\'t know zoe' , (done) ->
        bob.createRelationshipFrom zoe, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship.start.data._id).to.be.equal (String) zoe._id
          expect(relationship.end.data._id).to.be.equal (String) bob._id
          done()

    describe '#createRelationshipBetween()', ->

      it 'expects to create a relationship between two documents (bidirectional)', (done) ->
        alice.createRelationshipBetween bob, 'follows', {}, (err, relationships) ->
          expect(relationships).have.length 2
          expect(err).to.be null
          names = {}
          for relation in relationships
            names[relation.start.document.name] = true
          expect(names).to.only.have.keys( 'alice', 'bob' )
          # TODO: we should also test, that we get the correct relationships via incoming + outgoing
          # maybe a cypher query could be a good proof here
          done()

    describe '#removeRelationshipsTo', ->

      it 'expect to remove Relationships to other document', (done) ->
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

    describe '#removeRelationships', ->

      it 'expect to remove all relationship of specific kind', (done) ->
        zoe.createRelationshipTo bob, 'follows', (err, relationship) ->
          expect(err).to.be null
          zoe.createRelationshipTo alice, 'follows', (err, relationship) ->
            expect(err).to.be null
            # zoe follows bob and alice
            zoe.allRelationships 'follows', (err, relationships) ->
              expect(err).to.be null
              expect(relationships).to.have.length 2
              # zoe follows nobody
              zoe.removeRelationships 'follows', (err, relationships) ->
                expect(err).to.be null
                zoe.allRelationships 'follows', (err, relationships) ->
                  expect(err).to.be null
                  expect(relationships).to.have.length 0
                  done()

    describe '#allRelationships()', ->

      it 'expect to get all people alice knows and all people that know alice', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].data.since).to.be.equal 'years'
          done()

      it 'expect to get all related documents', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].from).to.be.an 'object'
          expect(relationships[0].to).to.be.an 'object'
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'zoe', 'bob' )
          done()

    describe '#incomingRelationships()', ->

      it 'expects that alice is not known by anybody', (done) ->
        alice.incomingRelationships 'knows', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 0
          done()

    describe '#outgoingRelationships()', ->

      it 'expects that alice knows 2 people', (done) ->
        alice.outgoingRelationships 'knows', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 2
          done()

    describe '#shortestPath()', ->

      it 'expects to get the shortest path between two documents', (done) ->
        # delete all relationships between alice, bob + zoe
        # longest:  alice -> bob -> charles -> zoe
        # shortest: alice -> bob -> zoe
        alice.removeRelationships 'knows', -> bob.removeRelationships 'knows', -> zoe.removeRelationships 'knows', ->
          alice.createRelationshipTo bob, 'knows', ->  
            bob.createRelationshipTo charles, 'knows', ->
              bob.createRelationshipTo zoe, 'knows', ->
                charles.createRelationshipTo zoe, 'knows', ->
                  alice.shortestPathTo zoe, 'knows', (err, path) ->
                    expect(path).to.be.an 'object'
                    expect(err).to.be null
                    expectedPath = [ alice._id, bob._id, zoe._id ]
                    for node, i in path
                      expect(String(node._id)).be.equal String(expectedPath[i])
                    done()
      
      it 'expects to get a mongoose document instead of a native mongodb document', (done) ->
        alice.shortestPathTo zoe, 'knows', (err, path) ->
          expect(path).to.have.length 3
          expect(path[0].fullname).to.be.equal 'alice a.'
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

      it 'expect to get the id of the corresponding mongodb document from a node', (done) ->
        alice.getNode (err, node) ->
          expect(node.getMongoId()).to.be.equal (String) alice._id
          done()

    describe '#getDocument()', ->

      it 'expect to get equivalent document from mongodb to node', (done) ->
        alice.getNode (err, node) ->
          expect(node).to.be.an 'object'
          node.getDocument (err, doc) ->
            expect(doc).to.be.an 'object'
            expect(String(doc._id)).to.be.equal (String) alice._id
            done()





      
    
