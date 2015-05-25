#!/usr/bin/env ruby

path = "#{Dir.home}/neo4j_instances/"

`mkdir -p #{path}`

versions = {
  "neo4j-community-2.0.4" => 7010,
  "neo4j-community-2.1.8" => 7012,
  "neo4j-community-2.2.2" => 7014,
}

if ARGV[0] == 'start'
  puts "starting..."
  versions.each { |version, port|
    puts "#{version} on port #{port}"
    altPort = port+1
    # ensuring we are using the right for ports
    filename = "#{path}/#{version}/conf/neo4j-server.properties"
    text = File.read(filename)
    text = text.gsub(/^(\s*org\.neo4j\.server\.webserver\.port\s*)(=\s*)(.+)$/, '\1='+port.to_s)
    text = text.gsub(/^(\s*org\.neo4j\.server\.webserver\.https\.port\s*)(=\s*)(.+)$/, '\1='+altPort.to_s)
    File.open(filename, "w") {|file| file.puts text }
    `#{path}/#{version}/bin/neo4j start`
  }
elsif ARGV[0] == 'stop'
  puts "stoppping..."
  versions.each { |version, port|
    puts "#{version} on port #{port}"
    `#{path}/#{version}/bin/neo4j stop`
  }
elsif ARGV[0] == 'install'
  versions.each { |version, port|
    puts "Installing #{version}"
    `cd #{path} && wget http://neo4j.com/artifact.php?name=#{version}-unix.tar.gz`
    `cd #{path} && tar zxvf artifact.php?name=#{version}-unix.tar.gz #{version}`
  }
else
  puts "Possible arguments: start|stop|install"
end