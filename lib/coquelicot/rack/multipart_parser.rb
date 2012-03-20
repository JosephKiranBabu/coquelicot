# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012 potager.org <jardiniers@potager.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'rack/multipart'
require 'rack/utils'
require 'multipart_parser/reader'

module Coquelicot::Rack
  class ManyFieldsStep < Struct.new(:block)
    def initialize(block)
      super
      @params = Rack::Utils::KeySpaceConstrainedParams.new
    end

    def call_handler
      block.call(indifferent_params(@params.to_params_hash)) unless block.nil?
    end

    def add_param(name, data)
      Rack::Utils.normalize_params(@params, name, data)
    end

    # borrowed from Sinatra::Base
    def indifferent_params(params)
      params = indifferent_hash.merge(params)
      params.each do |key, value|
        next unless value.is_a?(Hash)
        params[key] = indifferent_params(value)
      end
    end

    # borrowed from Sinatra::Base
    def indifferent_hash
      Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
    end
  end
  class FieldStep < Struct.new(:name, :block) ; end
  class FileStep < Struct.new(:name, :block) ; end

  class MultipartParser
    BUFFER_SIZE = 4096

    class << self
      alias :create :new

      def parse(env, &block)
        parser = MultipartParser.create(env)
        yield parser
        parser.send(:run)
      end

      alias :new :parse
    end

    # Run the given block before first field
    def start(&block)
      raise ArgumentError.new('#start requires a block') if block.nil?
      @start << block
    end

    # Parse any number of fields and execute the given block once the next step
    # has been reached
    def many_fields(&block)
      @steps << ManyFieldsStep.new(block)
    end

    # Parse the given field and execute the given block. If no block is given
    # the content of the field will be lost.
    def field(name, &block)
      @steps << FieldStep.new(name, block)
    end

    # Parse a file field with the given name
    #
    # The block will receive the filename, content type and a 'reader' proc.
    # The later MUST use the '#call' method to retreive the next part of file
    # content. It will return 'nil' once end of file has been reached.
    def file(name, &block)
      @steps << FileStep.new(name, block)
    end

    # Run the given block when reaching the end of the multipart data
    #
    # Subsequent calls will be run in the reverse order
    def finish(&block)
      raise ArgumentError.new('#finish requires a block') if block.nil?
      @finish.unshift block
    end

  private

    def initialize(env)
      @env = env
      @start = []
      @finish = []
      @steps = []
    end

    def run
      @io = @env['rack.input']

      @reader = ::MultipartParser::Reader.new(boundary)
      @reader.on_error do |msg|
        @events << [:error, msg]
      end
      @reader.on_part do |part|
        @events << [:part, part]
        part.on_data { |data| @events << [:part_data, data] }
        part.on_end  { @events << [:part_end] }
      end

      @start.each { |block| block.call }

      @events = []
      parse_input do |event, *args|
        case event
          when :error
            msg = args.shift
            raise EOFError.new("Unable to parse request body: #{msg}")
          when :part
            part = args.shift
            handle_part part
          when :part_data, :part_end
            raise StandardError.new("Out of order: #{event}")
        end
      end

      @current_step.call_handler if @current_step.is_a? ManyFieldsStep
      @finish.each { |block| block.call }
    end

    def parse_input(&block)
      loop do
        block.call(*@events.shift) until @events.empty?

        buf = @io.read(BUFFER_SIZE)
        break if buf.nil?
        @reader.write buf
        break if @reader.ended? && @events.empty?
      end
    end

    def boundary
      ::MultipartParser::Reader.extract_boundary_value(@env['CONTENT_TYPE'])
    end

    def handle_part(part)
      previous, @current_step = @current_step, lookup_steps!(part.name)
      if @current_step.nil?
        if previous.is_a? ManyFieldsStep
          # we can still parse more fields
          @current_step, previous = previous, nil
        else
          # a new part and no more steps, something is wrong!
          raise EOFError.new("Unexpected part #{part.name}")
        end
      end

      if previous.is_a? ManyFieldsStep
          # call handler if we are moving to more specific steps
          previous.call_handler unless @current_step.is_a? ManyFieldsStep
      end

      case @current_step
        when ManyFieldsStep
          buf = ''
          parse_input do |event, *args|
           case event
             when :part_data
               data = args.shift
               buf << data
             when :part_end
               @current_step.add_param(part.name, buf)
               return
             when :error, :part
               raise StandardError.new("Out of order: #{event}")
           end
        end
        when FieldStep
          buf = ''
          parse_input do |event, *args|
           case event
             when :part_data
               data = args.shift
               buf << data
             when :part_end
               @current_step.block.call(buf) unless @current_step.block.nil?
               return
             when :error, :part
               raise StandardError.new("Out of order: #{event}")
           end
        end
        when FileStep
          @current_step.block.call(part.filename, part.mime, lambda {
            value = nil
            parse_input do |event, *args|
              case event
                when :part_data
                   value = args.shift
                   break
                when :part_end
                   value = nil
                   break
                when :error, :part
                  raise StandardError.new("Out of order: #{event}")
              end
            end
            value
          })
      end
    end

    def lookup_steps!(name)
      index = 0
      found = nil
      while current = @steps[index]
        case current
          when FieldStep, FileStep
            if current.name.to_s == name
              found = index
              break
            end
          when ManyFieldsStep
            unless found && @steps[found].is_a?(ManyFieldsStep)
              found = index
            end
        end
        index += 1
      end
      return nil if found.nil?
      @steps.slice!(0, found)
      @steps[0]
    end
  end
end
