module Ameba::Rule
  # A rule that enforces method names to be in underscored case.
  #
  # For example, these are considered valid:
  #
  # ```
  # class Person
  #   def first_name
  #   end
  #
  #   def date_of_birth
  #   end
  #
  #   def homepage_url
  #   end
  # end
  # ```
  #
  # And these are invalid method names:
  #
  # ```
  # class Person
  #   def firstName
  #   end
  #
  #   def date_of_Birth
  #   end
  #
  #   def homepageURL
  #   end
  # end
  # ```
  struct MethodNames < Base
    def test(source)
      AST::Visitor.new self, source
    end

    def test(source, node : Crystal::Def)
      return if (expected = node.name.underscore) == node.name

      source.error self, node.location,
        "Method name should be underscore-cased: #{expected}, not #{node.name}"
    end
  end
end