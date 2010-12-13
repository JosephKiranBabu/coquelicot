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

require 'json'

class Haml::Engine
  include GetText

  # Inject _ gettext into plain text and tag plain text calls
  def push_plain(text)
    super(_(text))
  end
  def parse_tag(line)
    tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
      nuke_inner_whitespace, action, value, last_line = super(line)
    value = _(value) unless action && action != '!' || action == '!' && value[0..0] == '=' || value.empty?
    # translate inline ruby code too
    value.gsub!(/_\('([^']+)'\)/) {|m| '\''+_($1)+'\''} unless action != '=' || value.empty?
    attributes_hashes.each{|h| h.each{|v| v.gsub!(/_\('([^']+)'\)/){|m| '\''+_($1)+'\''} if v.is_a? String} unless h.nil? || h.empty?} unless attributes_hashes.nil? || attributes_hashes.empty?
    [tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
        nuke_inner_whitespace, action, value, last_line]
  end
  def push_flat_markdown(line)
    text = line.full.dup
    text = "" unless text.gsub!(/^#{@flat_spaces}/, '')
    text = _(text) if text != ''
    @filter_buffer << "#{text}\n"
  end
  def push_flat_javascript(line)
    text = line.full.dup
    text.gsub!(/_\('(([^']|\\')+)'\)/) {|m| _($1).to_json }
    @filter_buffer << "#{text}\n"
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
