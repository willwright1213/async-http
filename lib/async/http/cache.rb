# frozen_string_literal: true

# Copyright, 2020, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'async/http/client'
require 'protocol/http/headers'
require 'protocol/http/middleware'
require 'async/clock'

require_relative 'body/cachable'

module Async
	module HTTP
		class Cache < ::Protocol::HTTP::Middleware
			CACHE_CONTROL  = 'cache-control'
			
			class Response < ::Protocol::HTTP::Response
				def initialize(response, body)
					@generated_at = Async::Clock.now
					
					super(
						response.version,
						response.status,
						response.headers.dup,
						body,
						response.protocol
					)
					
					@max_age = @headers[CACHE_CONTROL]&.max_age
				end
				
				def cachable?
					if cache_control = @headers[CACHE_CONTROL]
						if cache_control.private?
							return false
						end
						
						if cache_control.public?
							return true
						end
					end
				end
				
				attr :generated_at
				
				def age
					Async::Clock.now - @generated_at
				end
				
				def expired?
					self.age > @max_age
				end
				
				def dup
					dup = super
					
					dup.body = @body.dup
					dup.headers = @headers.dup
					
					return dup
				end
			end
			
			def initialize(app, responses = {})
				super(app)
				
				@count = 0
				
				@responses = {}
			end
			
			attr :count
			
			def key(request)
				[request.authority, request.method, request.path]
			end
			
			def cachable?(request)
				request.method == 'GET' || request.method == 'HEAD'
			end
			
			def wrap(request, key, response)
				Body::Cachable.wrap(response) do |body|
					response = Response.new(response, body)
					
					if response.cachable?
						@responses[key] = response
					end
				end
			end
			
			def call(request)
				key = self.key(request)
				
				if response = @responses[key]
					Async.logger.info(self) {"Cache hit for #{key}..."}
					@count += 1
					
					if response.expired?
						Async.logger.info(self) {"Cache expired for #{key}..."}
						@responses.delete(key)
					else
						# Create a dup of the response:
						return response.dup
					end
				end
				
				if cachable?(request)
					Async.logger.info(self) {"Wrapping #{key}..."}
					return wrap(request, key, super)
				else
					Async.logger.info(self) {"Cache miss for #{key}..."}
					return super
				end
			end
		end
	end
end
