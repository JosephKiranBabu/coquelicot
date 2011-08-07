#!/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__),'..','lib')) << File.expand_path(File.join(File.dirname(__FILE__),'..'))
require 'coquelicot_app'

Coquelicot::Depot.new(Coquelicot.settings.depot_path).gc!