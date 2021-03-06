require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require 'v8'

describe Gene::JavascriptInterpreter do
  before do
    @interpreter = Gene::JavascriptInterpreter.new
    @ctx = V8::Context.new
  end

  it "(var a = null)" do
    @ctx.eval @interpreter.parse_and_process(example.description)
    @ctx['a'].should == nil
  end

  it "[1 2]" do
    result = @ctx.eval @interpreter.parse_and_process(example.description)
    result.to_a.should == [1, 2]
  end

  it "(class A)" do
    pending "ES6 not supported"
    result = @ctx.eval @interpreter.parse_and_process(example.description)
    result.name.should == 'A'
  end

  it "(1 + 2)" do
    result = @ctx.eval @interpreter.parse_and_process(example.description)
    result.should == 3
  end

  it "('a' + 'b')" do
    result = @ctx.eval @interpreter.parse_and_process(example.description)
    result.should == 'ab'
  end

  it "(var a = 1)" do
    @ctx.eval @interpreter.parse_and_process(example.description)
    @ctx['a'].should == 1
  end

  describe "conditions" do
    it "(if true 1)" do
      result = @ctx.eval @interpreter.parse_and_process(example.description)
      result.should == 1
    end

    it "(if false 1 2)" do
      result = @ctx.eval @interpreter.parse_and_process(example.description)
      result.should == 2
    end
  end

  describe "functions" do
    it "(function test [] [])" do
      @ctx.eval @interpreter.parse_and_process(example.description)
      @ctx['test'].is_a?(V8::Function).should == true
    end

    it "
      (function inc [arg] [(return arg + 1)])
      (inc 1)
    " do
      result = @interpreter.parse_and_process(example.description) do |code|
        @ctx.eval code
      end
      result.should == 2
    end
  end

  describe "advanced" do

    # Implement below
    #var DynamicDate = {
    #  calculateDays: function(month, year) {
    #    if ([4, 6, 9, 11].indexOf(month) >= 0) { return 30; }  /* April, June, September, November */
    #
    #    if (month == 2) { /* February */
    #      if (this.leapYear(year))
    #        return 29;
    #      else
    #        return 28;
    #    }
    #
    #    return 31;
    #  },
    #
    #  leapYear: function(year) {
    #    /* Any year divisible by 4 except those divisible by 100 except 400 */
    #    return ( ((year % 4 == 0) && (year % 100 != 0)) || ( year % 400 == 0) )
    #  }
    #}
    it "
      (var DynamicDate = {
        calculateDays : (function [month year] [
          (if (([4 6 9 11] .indexOf month) >= 0) (return 30)) # April, June, September, November
          (if (month == 2) # February
            (if (this .leapYear year) (return 29) (return 28))
          )
          (return 31)
        ]),
        leapYear : (function [year] [
          # Any year divisible by 4 except those divisible by 100 except 400
          (return ((year % 4 == 0) && (year % 100 != 0) || (year % 400 == 0)))
        ])
      })
    " do
      pending "Test fails."
      @ctx.eval @interpreter.parse_and_process(example.description)
      @ctx.eval('DynamicDate.calculateDays(4, 1990)').should == 30
      @ctx.eval('DynamicDate.calculateDays(1, 1990)').should == 31
      @ctx.eval('DynamicDate.calculateDays(2, 1980)').should == 29
      @ctx.eval('DynamicDate.calculateDays(2, 1900)').should == 28
      @ctx.eval('DynamicDate.calculateDays(2, 1901)').should == 28
    end
  end
end
