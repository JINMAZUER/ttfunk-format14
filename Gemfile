# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'prawn', git: 'https://github.com/JINMAZUER/prawn-format14.git', branch: 'extend-format14'

# Evaluate Gemfile.local if it exists
if File.exist?("#{__FILE__}.local")
  instance_eval(File.read("#{__FILE__}.local"), "#{__FILE__}.local")
end
