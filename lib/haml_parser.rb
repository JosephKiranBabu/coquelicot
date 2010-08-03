# Adapted from sinitra-hat: http://github.com/nanoant/sinatra-hat/
#
# Copyright (c) 2009 Adam Strzelecki
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'gettext/tools/parser/ruby'
require 'haml'

class String
  def escape_single_quotes
    self.gsub(/'/, "\\\\'")
  end
end

class Haml::Engine
  # Overriden function that parses Haml tags
  # Injects gettext call for plain text action.
  def parse_tag(line)
    tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
      nuke_inner_whitespace, action, value, last_line = super(line)
    @precompiled << "_('#{value.escape_single_quotes}')\n" unless action && action != '!' || action == '!' && value[0..0] == '=' || value.empty?
    [tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
        nuke_inner_whitespace, action, value, last_line]
  end
  # Overriden function that producted Haml plain text
  # Injects gettext call for plain text action.
  def push_plain(text)
    @precompiled << "_('#{text.escape_single_quotes}')\n"
  end
  def push_flat_markdown(line)
    text = line.unstripped
    return if text == ''
    @precompiled << "_('#{text.escape_single_quotes}')\n"
  end
  def push_flat_javascript(line)
    text = line.unstripped
    return if text == ''
    text.gsub(/_\('(([^']|\\')+)'\)/) do |m|
      @precompiled << "_('#{$1}')"
    end
  end
  def push_flat(line)
    return super(line) if @gettext_filters.nil? || !@gettext_filters.last
    return send("push_flat_#{@gettext_filters.last}".to_sym, line)
  end
  def start_filtered(name)
    @gettext_filters ||= []
    @gettext_filters.push(name) if ['markdown', 'javascript'].include? name
    super
  end
  def close_filtered(filter)
    @gettext_filters.pop
    super
  end
end

# Haml gettext parser
module HamlParser
  module_function
 
  def target?(file)
    File.extname(file) == ".haml"
  end
 
  def parse(file, ary = [])
    haml = Haml::Engine.new(IO.readlines(file).join)
    code = haml.precompiled.split(/$/)
    GetText::RubyParser.parse_lines(file, code, ary)
  end
end
 
GetText::RGetText.add_parser(HamlParser)
