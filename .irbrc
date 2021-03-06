puts "Loading #{__FILE__}"

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'v8'

begin
  require 'gene'
rescue LoadError
  puts "Use bundle exec irb if error is thrown because of gems pulled from github"
end

P = Parser           = Gene::Parser
# # C = CoreInterpreter  = Gene::CoreInterpreter
# # R = RubyInterpreter  = Gene::RubyInterpreter
# # J = JavascriptInterpreter = Gene::JavascriptInterpreter
# # F = FileSystem       = Gene::FileSystem
# C = Compiler         = Gene::Lang::Compiler

# @ctx = V8::Context.new
# @ctx.eval File.read "gene-js/build/src/index.js"

# @compiler = C.new

# def compile input
#   puts "-" * 80
#   puts
#   puts input.gsub(/^\s{2}/, '')
#   puts
#   output = @compiler.parse_and_process input
#   puts "|" * 80
#   puts "V" * 80
#   puts
#   puts output.to_s.gsub(/^\s{6}/, '')
#   puts
#   puts "=" * 80
#   puts
# end

# compile <<-CODE
#   (var a 1)
# CODE

@app = Gene::Lang::Application.new
@app.load_core_libs
@app.load File.expand_path(File.dirname(__FILE__) + '/lib/gene/lang/gene2js.gene')
@app.load File.expand_path(File.dirname(__FILE__) + '/lib/gene/lang/compiler.gene')

@ctx = V8::Context.new
@ctx.eval File.read "gene-js/build/src/index.js"