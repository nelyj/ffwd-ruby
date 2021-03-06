# $LICENSE
# Copyright 2013-2014 Spotify AB. All rights reserved.
#
# The contents of this file are licensed under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with the
# License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require 'eventmachine'
require 'em/protocols/frame_object_protocol'

require 'ffwd/connection'
require 'ffwd/handler'
require 'ffwd/logging'
require 'ffwd/plugin'
require 'ffwd/protocol'
require 'ffwd/event'
require 'ffwd/metric'

require_relative 'protobuf/serializer'

module FFWD::Plugin::Protobuf
  include FFWD::Plugin
  include FFWD::Logging

  register_plugin "protobuf"

  class OutputUDP < FFWD::Handler
    def self.plugin_type
      "protobuf_udp_out"
    end

    def initialize connect, config
      @connect = connect
    end

    def send_all events, metrics
      events.each do |event|
        send_event event
      end

      metrics.each do |metric|
        send_metric metric
      end
    end

    def send_event event
      @connect.send_data Serializer.dump_event(event)
    end

    def send_metric metric
      @connect.send_data Serializer.dump_metric(metric)
    end
  end

  class InputUDP < FFWD::Connection
    include FFWD::Logging
    include EM::Protocols::FrameObjectProtocol

    def initialize bind, core, config
      @bind = bind
      @core = core
    end

    def self.plugin_type
      "protobuf"
    end

    def receive_data datagram
      Serializer.load(datagram) do |type, data|
        if type == :event
          @core.input.event data
          @bind.increment :received_events
          next
        end

        if type == :metric
          @core.input.metric data
          @bind.increment :received_metrics
          next
        end
      end
    rescue => e
      log.error "Failed to receive data", e

      if log.debug?
        log.debug("DUMP: " + FFWD.dump2hex(datagram))
      end
    end
  end

  DEFAULT_HOST = "localhost"
  DEFAULT_PORT = 19091
  DEFAULT_PROTOCOL = 'udp'

  OUTPUTS = {:udp => OutputUDP}
  INPUTS = {:udp => InputUDP}

  def self.setup_output config
    config[:host] ||= DEFAULT_HOST
    config[:port] ||= DEFAULT_PORT
    config[:protocol] ||= DEFAULT_PROTOCOL

    protocol = FFWD.parse_protocol config[:protocol]

    unless handler = OUTPUTS[protocol.family]
      raise "No handler for protocol family: #{protocol.family}"
    end

    protocol.connect config, log, handler
  end

  def self.setup_input config
    config[:host] ||= DEFAULT_HOST
    config[:port] ||= DEFAULT_PORT
    config[:protocol] ||= DEFAULT_PROTOCOL

    protocol = FFWD.parse_protocol config[:protocol]

    unless connection = INPUTS[protocol.family]
      raise "No connection for protocol family: #{protocol.family}"
    end

    protocol.bind config, log, connection
  end
end
