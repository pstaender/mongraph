sequence = require('futures').sequence.create()

sequence

  .then (next) ->
    
    {suite}  = require('./creating_records')

    suite.on "complete", ->      
      console.log "\n**Fastest** is " + @filter("fastest").pluck("name")
      console.log "\n**Slowest** is " + @filter("slowest").pluck("name")
      console.log "\n"
      next()

    console.log "\n### CREATING RECORDS\n"
    suite.run async: true
  
  .then (next) ->
    
    {suite} = require('./finding_records')

    suite.on "complete", ->      
      console.log "\n**Fastest** is " + @filter("fastest").pluck("name")
      console.log "\n**Slowest** is " + @filter("slowest").pluck("name")
      console.log "\n"
      next()

    console.log "\n### FINDING RECORDS\n"
    suite.run async: true

  .then (next) ->
    
    console.log 'done... exiting'
    process.exit(0)
