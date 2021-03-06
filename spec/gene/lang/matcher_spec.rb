require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe Gene::Lang::Matcher do
  before  do
    @matcher = Gene::Lang::Matcher.new
  end

  it "data matcher" do
    @matcher.from_array [
      Gene::Types::Symbol.new('arg1'),
    ]

    @matcher.data_matchers.size.should == 1
    data_matcher = @matcher.data_matchers[0]
    data_matcher.name.should == 'arg1'
  end

  it "matches a bare item" do
    @matcher.from_array Gene::Types::Symbol.new('arg1')

    @matcher.data_matchers.size.should == 1
    data_matcher = @matcher.data_matchers[0]
    data_matcher.name.should == 'arg1'
  end

  it "data matcher with default value" do
    @matcher.from_array [
      Gene::Types::Symbol.new('arg1'),
      Gene::Types::Symbol.new('='),
      'value',
    ]

    @matcher.data_matchers.size.should == 1
    data_matcher = @matcher.data_matchers[0]
    data_matcher.name.should == 'arg1'
    data_matcher.default_value.should == 'value'
  end

  it "expandable data matcher" do
    @matcher.from_array [
      Gene::Types::Symbol.new('arg1...'),
    ]

    @matcher.data_matchers.size.should == 1
    data_matcher = @matcher.data_matchers[0]
    data_matcher.name.should == 'arg1'
    data_matcher.expandable.should be_true
  end

  it "data matcher index & end index" do
    @matcher.from_array [
      Gene::Types::Symbol.new('arg1'),
      Gene::Types::Symbol.new('arg2...'),
    ]

    @matcher.data_matchers.size.should == 2

    data_matcher1 = @matcher.data_matchers[0]
    data_matcher1.name.should == 'arg1'
    data_matcher1.expandable.should be_false
    data_matcher1.index.should == 0

    data_matcher2 = @matcher.data_matchers[1]
    data_matcher2.name.should == 'arg2'
    data_matcher2.expandable.should be_true
    data_matcher2.index.should == 1
    data_matcher2.end_index.should == -1
  end

  it "prop matcher" do
    @matcher.from_array [
      Gene::Types::Symbol.new('^^arg1'),
    ]

    @matcher.data_matchers.size.should == 0
    @matcher.prop_matchers.size.should == 1
    prop_matcher = @matcher.prop_matchers['arg1']
    prop_matcher.name.should == 'arg1'
  end

  it "prop matcher with default value" do
    @matcher.from_array [
      Gene::Types::Symbol.new('^arg1'),
      'value',
    ]

    @matcher.data_matchers.size.should == 0
    @matcher.prop_matchers.size.should == 1
    prop_matcher = @matcher.prop_matchers['arg1']
    prop_matcher.name.should == 'arg1'
    prop_matcher.default_value.should == 'value'
  end

  it "name conflict" do
    lambda {
      @matcher.from_array [
        Gene::Types::Symbol.new('arg1'),
        Gene::Types::Symbol.new('arg1'),
      ]
    }.should raise_error
  end

end
