#!/usr/bin/ruby -wKU
#
# = Regular Expression Construction
#
# Complex regular expressions are hard to construct and even harder to
# read.  The Re library allows users to construct complex regular
# expressions from simpler expressions.  For example, consider the
# following regular expression that will parse dates:
#
#    /\A((?:19|20)[0-9]{2})[\- \/.](0[1-9]|1[012])[\- \/.](0[1-9]|[12][0-9]|3[01])\z/
#
# Using the Re library, That regular expression can be built
# incrementaly from smaller, easier to understand expressions.
# Perhaps something like this:
#
#   require 're'
#
#   include Re
#
#   delim                = re.any("- /.")
#   century_prefix       = re("19") | re("20")
#   under_ten            = re("0") + re.any("1-9")
#   ten_to_twelve        = re("1") + re.any("012")
#   ten_and_under_thirty = re.any("12") + re.any("0-9")
#   thirties             = re("3") + re.any("01")
#          
#   year = (century_prefix + re.digit.repeat(2)).capture(:year)
#   month = (under_ten | ten_to_twelve).capture(:month)
#   day = (under_ten | ten_and_under_thirty | thirties).capture(:day)
#          
#   date = (year + delim + month + delim + day).all
#
# Although it is more code, the individual pieces are smaller and
# easier to independently verify.  As an additional bonus, the capture
# groups can be retrieved by name:
#
#   result = date.match("2009-01-23")
#   result.data(:year)   # => "2009"
#   result.data(:month)  # => "01"
#   result.data(:day)    # => "23"
#
# == Usage
#
#   include Re
#
#   number = re.any("0-9").all
#   if number =~ string
#     puts "Matches!"
#   else
#     puts "No Match"
#   end
#
# == Examples
#
#   re("a")                -- matches "a"
#   re("a") + re("b")      -- matches "ab"
#   re("a") | re("b")      -- matches "a" or "b"
#   re("a").many           -- matches "", "a", "aaaaaa"
#   re("a").one_or_more    -- matches "a", "aaaaaa", but not ""
#   re("a").optional       -- matches "" or "a"
#   re("a").all            -- matches "a", but not "xab"
#
# See Re::Rexp for a complete list of expressions.
#
# Using re without an argument allows access to a number of common
# regular expression constants.  For example:
#
#   re.space / re.spaces  -- matches " ", "\n" or "\t"
#   re.digit / re.digits  -- matches a digit / sequence of digits
#
# Also, re without arguments can also be used to construct character
# classes:
#
#   re.any                -- Matches any charactor
#   re.any("abc")         -- Matches "a", "b", or "c"
#   re.any("0-9")         -- Matches the digits 0 through 9
#   re.any("A-Z", "a-z", "0-9", "_")
#                         -- Matches alphanumeric or an underscore
#
# See Re::ConstructionMethods for a complete list of common constants
# and character class functions.
#
# See Re.re, Re::Rexp, and Re::ConstructionMethods for details.
#
#
# == License and Copyright
#
# Copyright 2009 by Jim Weirich (jim.weirich@gmail.com).
# All rights Reserved.
#
# Re is provided under the MIT open source license (see MIT-LICENSE)
#
# == Links:
#
# Documentation :: http://re-lib.rubyforge.org
# Source        :: http://github.com/jimweirich/re
# GemCutter     :: http://gemcutter.org/gems/re
# Download      :: http://rubyforge.org/frs/?group_id=9329
# Bug Tracker   :: http://www.pivotaltracker.com/projects/47758
# Author        :: jim.weirich@gmail.com
#
module Re
  
  module Version
    NUMBERS = [
      MAJOR = 0,
      MINOR = 0,
      BUILD = 4,
      BETA  = nil,
    ].compact
  end
  VERSION = Version::NUMBERS.join('.')
  
  # Re::Result captures the result of a match and allows lookup of the
  # captured groups by name.
  class Result
    # Create a Re result object with the match data and the original
    # Re::Rexp object.
    def initialize(match_data, rexp)
      @match_data = match_data
      @rexp = rexp
    end
    
    # Return the text of the full match.
    def full_match
      @match_data[0]
    end
    
    # Return the text of the named capture data.
    def [](name)
      index = @rexp.capture_keys.index(name)
      index ? @match_data[index+1] : nil
    end
  end

  # Precedence levels for regular expressions:

  GROUPED = 4                   # (r), [chars]      :nodoc:
  POSTFIX = 3                   # r*, r+, r?        :nodoc:
  CONCAT  = 2                   # r + r, literal    :nodoc:
  ALT     = 1                   # r | r             :nodoc:

  # Mode Bits

  MULTILINE_MODE = Regexp::MULTILINE
  IGNORE_CASE_MODE = Regexp::IGNORECASE

  # Constructed regular expressions.
  class Rexp
    attr_reader :level, :options, :capture_keys

    # Create a regular expression from the string.  The regular
    # expression will have a precedence of +level+ and will recognized
    # +keys+ as a list of capture keys.
    def initialize(string, level, keys, options=0)
      @raw_string = string
      @level = level
      @capture_keys = keys
      @options = options
    end
    
    # Return a Regexp from the the constructed regular expression.
    def regexp
      @regexp ||= Regexp.new(encoding)
    end

    # Does it match a string? (returns Re::Result if match, nil otherwise)
    def match(string)
      md = regexp.match(string)
      md ? Result.new(md, self) : nil
    end
    alias =~ match
    
    def name_map
      result = {}
      capture_keys.each_with_index do |key, i|
        result[key] = i + 1
      end
      result
    end

    # New regular expresion that matches the concatenation of self and
    # other.
    def +(other)
      Rexp.new(parenthesized_encoding(CONCAT) + other.parenthesized_encoding(CONCAT),
        CONCAT,
        capture_keys + other.capture_keys)
    end

    # New regular expresion that matches either self or other.
    def |(other)
      Rexp.new(parenthesized_encoding(ALT) + "|" + other.parenthesized_encoding(ALT),
        ALT,
        capture_keys + other.capture_keys)
    end

    # New regular expression where self is optional.
    def optional
      Rexp.new(parenthesized_encoding(POSTFIX) + "?", POSTFIX, capture_keys)
    end

    # New regular expression that matches self many (zero or more)
    # times.
    def many
      Rexp.new(parenthesized_encoding(POSTFIX) + "*", POSTFIX, capture_keys)
    end

    # New regular expression that matches self many (zero or more)
    # times (non-greedy version).
    def many!
      Rexp.new(parenthesized_encoding(POSTFIX) + "*?", POSTFIX, capture_keys)
    end

    # New regular expression that matches self one or more times.
    def one_or_more
      Rexp.new(parenthesized_encoding(POSTFIX) + "+", POSTFIX, capture_keys)
    end

    # New regular expression that matches self one or more times
    # (non-greedy version).
    def one_or_more!
      Rexp.new(parenthesized_encoding(POSTFIX) + "+?", POSTFIX, capture_keys)
    end

    # New regular expression that matches self between +min+ and +max+
    # times (inclusive).  If +max+ is omitted, then it must match self
    # exactly exactly +min+ times.
    def repeat(min, max=nil)
      if min && max
        Rexp.new(parenthesized_encoding(POSTFIX) + "{#{min},#{max}}", POSTFIX, capture_keys)
      else
        Rexp.new(parenthesized_encoding(POSTFIX) + "{#{min}}", POSTFIX, capture_keys)
      end
    end

    # New regular expression that matches self at least +min+ times.
    def at_least(min)
      Rexp.new(parenthesized_encoding(POSTFIX) + "{#{min},}", POSTFIX, capture_keys)
    end

    # New regular expression that matches self at most +max+ times.
    def at_most(max)
      Rexp.new(parenthesized_encoding(POSTFIX) + "{0,#{max}}", POSTFIX, capture_keys)
    end

    # New regular expression that matches self across the complete
    # string.
    def all
      self.begin.very_end
    end

    # New regular expression that matches self across most of the
    # entire string (trailing new lines are not required to match).
    def almost_all
      self.begin.end
    end

    # New regular expression that matches self at the beginning of a line.
    def bol
      Rexp.new("^" + parenthesized_encoding(CONCAT), CONCAT, capture_keys)
    end

    # New regular expression that matches self at the end of the line.
    def eol
      Rexp.new(parenthesized_encoding(CONCAT) + "$", CONCAT, capture_keys)
    end

    # New regular expression that matches self at the beginning of a string.
    def begin
      Rexp.new("\\A" + parenthesized_encoding(CONCAT), CONCAT, capture_keys)
    end

    # New regular expression that matches self at the end of a string
    # (trailing new lines are allowed to not match).
    def end
      Rexp.new(parenthesized_encoding(CONCAT) + "\\Z", CONCAT, capture_keys)
    end

    # New regular expression that matches self at the very end of a string
    # (trailing new lines are required to match).
    def very_end
      Rexp.new(parenthesized_encoding(CONCAT) + "\\z", CONCAT, capture_keys)
    end

    # New expression that matches self across an entire line.
    def line
      self.bol.eol
    end

    # New regular expression that is grouped, but does not cause the
    # capture of a match.  The Re library normally handles grouping
    # automatically, so this method shouldn't be needed by client
    # software for normal operations.
    def group
      Rexp.new("(?:" + encoding + ")", GROUPED, capture_keys)
    end

    # New regular expression that captures text matching self.  The
    # matching text may be retrieved from the Re::Result object using
    # the +name+ (a symbol) as the keyword.
    def capture(name)
      Rexp.new("(" + encoding + ")", GROUPED, [name] + capture_keys)
    end
    
    # New regular expression that matches self in multiline mode.
    def multiline
      Rexp.new(@raw_string, GROUPED, capture_keys, options | MULTILINE_MODE)
    end
    
    # Is this a multiline regular expression?  The multiline mode of
    # interior regular expressions are not reflected in value returned
    # by this method.
    def multiline?
      (options & MULTILINE_MODE) != 0
    end

    # New regular expression that matches self while ignoring case.
    def ignore_case
      Rexp.new(@raw_string, GROUPED, capture_keys, options | IGNORE_CASE_MODE)
    end

    # Does this regular expression ignore case?  Note that this only
    # queries the outer most regular expression.  The ignore case mode
    # of interior regular expressions are not reflected in value
    # returned by this method.
    def ignore_case?
      (options & IGNORE_CASE_MODE) != 0
    end

    # String representation of the constructed regular expression.
    def to_s
      regexp.to_s
    end
    
    protected

    # String representation with grouping if needed.
    #
    # If the precedence of the current Regexp is less than the new
    # precedence level, return the encoding wrapped in a non-capturing
    # group.  Otherwise just return the encoding.
    def parenthesized_encoding(new_level)
      if level >= new_level
        encoding
      else
        group.encoding
      end
    end
    
    # The string encoding of current regular expression.  The encoding
    # will include option flags if specified.
    def encoding
      if options == 0
        @raw_string
      else
        "(?#{encode_options}:" + @raw_string + ")"
      end
    end
    
    # Encode the options into a string (e.g "", "m", "i", or "mi")
    def encode_options          # :nodoc:
      (multiline? ? "m" : "") +
        (ignore_case? ? "i" : "")
    end
    private :encode_options

    # New regular expression that matches the literal characters in
    # +chars+.  For example, Re.literal("a(b)") will be equivalent to
    # /a\(b\)/.  Note that characters with special meanings in regular
    # expressions will be quoted.
    def self.literal(chars)
      new(Regexp.escape(chars), CONCAT, [])
    end

    # New regular expression constructed from a string representing a
    # ruby regular expression.  The raw string should represent a
    # regular expression with the highest level of precedence (you
    # should use parenthesis if it is not).
    def self.raw(re_string)     # :no-doc:
      new(re_string, GROUPED, [])
    end

    # Escape special characters found in character classes.
    def self.escape_any(chars)  # :nodoc:
      chars.gsub(/([\[\]\^\-])/) { "\\#{$1}" }
    end
  end

  
  # Construct a regular expression from the literal string.  Special
  # Regexp characters will be escaped before constructing the regular
  # expression.  If no literal is given, then the NULL regular
  # expression is returned.
  #
  # See Re for example usage.
  #
  def re(exp=nil)
    exp ? Rexp.literal(exp) : NULL
  end
  extend self
  
  # This module defines a number of methods returning common
  # pre-packaged regular expressions along with methods to create
  # regular expressions from character classes and other objects.
  # ConstructionMethods is mixed into the NULL Rexp object so that
  # re() without arguments can be used to access the methods.
  module ConstructionMethods
    
    ANY_CHAR =  Rexp.raw(".")
    
    # :call-seq:
    #   re.null
    #
    # Regular expression that matches the null string
    def null
      self
    end
    
    # :call-seq:
    #   re.any
    #   re.any(chars)
    #   re.any(range)
    #   re.any(chars, range, ...)
    #
    # Regular expression that matches a character from a character
    # class.
    #
    # +Any+ without any arguments will match any single character.
    # +Any+ with one or more arguments will construct a character
    # class for the arguments.  If the argument is a three character
    # string where the middle character is "-", then the argument
    # represents a range of characters.  Otherwise the arguments are
    # treated as a list of characters to be added to the character
    # class.
    #
    # Examples:
    #
    #   re.any                            -- matches any character
    #   re.any("aieouy")                  -- matches vowels
    #   re.any("0-9")                     -- matches digits
    #   re.any("A-Z", "a-z", "0-9")       -- matches alphanumerics
    #   re.any("A-Z", "a-z", "0-9", "_")  -- matches alphanumerics
    #                                        plus an underscore
    #
    def any(*chars)
      if chars.empty?
        ANY_CHAR
      else
        Rexp.new("[" + char_class(chars)  + "]", GROUPED, [])
      end
    end
    
    # :call-seq:
    #   re.none(chars)
    #   re.none(range)
    #   re.none(chars, range, ...)
    #
    # Regular expression that matches a character not in a character
    # class.
    #
    # +None+ with one or more arguments will construct a character
    # class for the given arguments.  If the argument is a three
    # character string where the middle character is "-", then the
    # argument represents a range of characters.  Otherwise the
    # arguments are treated as a list of characters to be added to the
    # character class.
    #
    # Examples:
    #
    #   re.none("aieouy")                 -- matches non-vowels
    #   re.any("0-9")                     -- matches non-digits
    #   re.any("A-Z", "a-z", "0-9")       -- matches non-alphanumerics
    #
    def none(*chars)
      Rexp.new("[^" + char_class(chars)  + "]", GROUPED, [])
    end

    def char_class(chars)
      any_chars = ''
      chars.each do |chs|
        if /^.-.$/ =~ chs
          any_chars << chs
        else
          any_chars << Rexp.escape_any(chs)
        end
      end
      any_chars
    end
    private :char_class

    # :call-seq:
    #   re.space
    #
    # Regular expression that matches any white space character.
    # (equivalent to /\s/)
    def space
      @space ||= Rexp.raw("\\s")
    end
    
    # :call-seq:
    #   re.spaces
    #
    # Regular expression that matches any sequence of white space
    # characters.  (equivalent to /\s+/)
    def spaces
      @spaces ||= space.one_or_more
    end
    
    # :call-seq:
    #   re.nonspace
    #
    # Regular expression that matches any non-white space character.
    # (equivalent to /\S/)
    def nonspace
      @nonspace ||= Rexp.raw("\\S")
    end
    
    # :call-seq:
    #   re.nonspaces
    #
    # Regular expression that matches any sequence of non-white space
    # characters.  (equivalent to /\S+/)
    def nonspaces
      @nonspaces ||= Rexp.raw("\\S").one_or_more
    end
    
    # :call-seq:
    #   re.word_char
    #
    # Regular expression that matches any word character.  (equivalent
    # to /\w/)
    def word_char
      @word_char ||= Rexp.raw("\\w")
    end
    
    # :call-seq:
    #   re.word
    #
    # Regular expression that matches any sequence of word characters.
    # (equivalent to /\w+/)
    def word
      @word ||= word_char.one_or_more
    end
    
    # :call-seq:
    #   re.break
    #
    # Regular expression that matches any break between word/non-word
    # characters.  This is a zero length match.  (equivalent to /\b/)
    def break
      @break ||= Rexp.raw("\\b")
    end
    
    # :call-seq:
    #   re.digit
    #
    # Regular expression that matches a single digit.  (equivalent to
    # /\d/)
    def digit
      @digit ||= any("0-9")
    end
    
    # :call-seq:
    #   re.digits
    #
    # Regular expression that matches a sequence of digits.
    # (equivalent to /\d+/)
    def digits
      @digits ||= digit.one_or_more
    end
    
    # :call-seq:
    #   re.hex_digit
    #
    # Regular expression that matches a single hex digit.  (equivalent
    # to /[A-Fa-f0-9]/)
    def hex_digit
      @hex_digit ||= any("0-9", "a-f", "A-F")
    end
    
    # :call-seq:
    #   re.hex_digits
    #
    # Regular expression that matches a sequence of hex digits
    # (equivalent to /[A-Fa-f0-9]+/)
    def hex_digits
      @hex_digits ||= hex_digit.one_or_more
    end
  end

  # Matches an empty string.  Additional common regular expression
  # construction methods are defined on NULL. See
  # Re::ConstructionMethods for details.
  NULL = Rexp.literal("")
  NULL.extend(ConstructionMethods)

end
