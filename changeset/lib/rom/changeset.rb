require 'dry/core/class_attributes'
require 'dry/core/cache'

require 'rom/constants'
require 'rom/initializer'

module ROM
  # Abstract Changeset class
  #
  # If you inherit from this class you need to configure additional settings
  #
  # @example define a custom changeset using :upsert command
  #   class NewTag < ROM::Changeset[:tags]
  #     command_type :upsert
  #   end
  #
  # @abstract
  class Changeset
    DEFAULT_COMMAND_OPTS = { mapper: false }.freeze

    extend Initializer
    extend Dry::Core::Cache
    extend Dry::Core::ClassAttributes

    # @!method self.command_type
    #   Get or set changeset command type
    #
    #   @overload command_type
    #     Return configured command_type
    #     @return [Symbol]
    #
    #   @overload command_type(identifier)
    #     Set relation identifier for this changeset
    #     @param [Symbol] identifier The command type identifier
    #     @return [Symbol]
    defines :command_type

    # @!method self.relation
    #   Get or set changeset relation identifier
    #
    #   @overload relation
    #     Return configured relation identifier for this changeset
    #     @return [Symbol]
    #
    #   @overload relation(identifier)
    #     Set relation identifier for this changeset
    #     @param [Symbol] identifier The relation identifier from the ROM container
    #     @return [Symbol]
    defines :relation

    # @!attribute [r] relation
    #   @return [Relation] The changeset relation
    param :relation

    # @!attribute [r] command_type
    #   @return [Symbol] a custom command identifier
    option :command_type, default: -> { self.class.command_type }

    # Create a changeset class preconfigured for a specific relation
    #
    # @example
    #   class NewUserChangeset < ROM::Changeset::Create[:users]
    #   end
    #
    #   user_repo.changeset(NewUserChangeset).data(name: 'Jane')
    #
    # @api public
    def self.[](relation_name)
      fetch_or_store([relation_name, self]) {
        Class.new(self) { relation(relation_name) }
      }
    end

    # Return a new changeset with provided relation
    #
    # New options can be provided too
    #
    # @param [Relation] relation
    # @param [Hash] new_options
    #
    # @return [Changeset]
    #
    # @api public
    def new(relation, new_options = EMPTY_HASH)
      self.class.new(relation, new_options.empty? ? options : options.merge(new_options))
    end

    # Persist changeset
    #
    # @example
    #   changeset = user_repo.changeset(name: 'Jane')
    #   changeset.commit
    #   # => { id: 1, name: 'Jane' }
    #
    # @return [Hash, Array]
    #
    # @api public
    def commit
      command.call
    end

    # Return string representation of the changeset
    #
    # @return [String]
    #
    # @api public
    def inspect
      %(#<#{self.class} relation=#{relation.name.inspect}>)
    end

    # Return a command for this changeset
    #
    # @return [ROM::Command]
    #
    # @api private
    def command
      relation.command(command_type, DEFAULT_COMMAND_OPTS)
    end
  end
end

require 'rom/changeset/stateful'
require 'rom/changeset/associated'

require 'rom/changeset/create'
require 'rom/changeset/update'
require 'rom/changeset/delete'
