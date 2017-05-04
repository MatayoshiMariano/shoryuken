module Shoryuken
  class Processor
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      worker = Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
      body = get_body(worker.class, sqs_msg)

      worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
        if body.present?
          params = perform_params(sqs_msg, body)
          worker.perform(params)
        else
          worker.perform
        end
      end
    rescue Exception => ex
      @manager.processor_failed(ex)
      raise
    ensure
      @manager.processor_done(queue)
    end

    private

    def perform_params(sqs_msg, body)
      {
        "sqs_msg" => sqs_msg
      }.merge(body)
    end

    def get_body(worker_class, sqs_msg)
      if sqs_msg.is_a? Array
        sqs_msg.map { |m| parse_body(worker_class, m) }
      else
        parse_body(worker_class, sqs_msg)
      end
    end

    def parse_body(worker_class, sqs_msg)
      body_parser = worker_class.get_shoryuken_options['body_parser']

      case body_parser
      when :json
        JSON.parse(sqs_msg.body)
      when Proc
        body_parser.call(sqs_msg)
      when :text, nil
        sqs_msg.body
      else
        if body_parser.respond_to?(:parse)
          # JSON.parse
          body_parser.parse(sqs_msg.body)
        elsif body_parser.respond_to?(:load)
          # see https://github.com/phstc/shoryuken/pull/91
          # JSON.load
          body_parser.load(sqs_msg.body)
        end
      end
    rescue => e
      logger.error { "Error parsing the message body: #{e.message}\nbody_parser: #{body_parser}\nsqs_msg.body: #{sqs_msg.body}" }
      raise
    end
  end
end
