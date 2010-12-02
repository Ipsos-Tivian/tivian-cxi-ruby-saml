# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{ruby-saml}
  s.version = "0.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["OneLogin LLC"]
  s.date = %q{2010-12-01}
  s.description = %q{SAML toolkit for Ruby on Rails}
  s.email = %q{support@onelogin.com}
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "lib/onelogin/saml.rb",
    "lib/onelogin/saml/authrequest.rb",
    "lib/onelogin/saml/response.rb",
    "lib/onelogin/saml/settings.rb",
    "lib/ruby-saml.rb",
    "lib/xml_sec.rb",
    "ruby-saml.gemspec",
    "test/response.txt",
    "test/ruby-saml_test.rb",
    "test/test_helper.rb"
  ]
  s.homepage = %q{http://github.com/onelogin/ruby-saml}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{SAML Ruby Tookit}
  s.test_files = [
    "test/ruby-saml_test.rb",
    "test/test_helper.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<xmlcanonicalizer>, ["= 0.1.0"])
      s.add_development_dependency(%q<shoulda>, [">= 0"])
      s.add_development_dependency(%q<mocha>, [">= 0"])
    else
      s.add_dependency(%q<xmlcanonicalizer>, ["= 0.1.0"])
      s.add_dependency(%q<shoulda>, [">= 0"])
      s.add_dependency(%q<mocha>, [">= 0"])
    end
  else
    s.add_dependency(%q<xmlcanonicalizer>, ["= 0.1.0"])
    s.add_dependency(%q<shoulda>, [">= 0"])
    s.add_dependency(%q<mocha>, [">= 0"])
  end
end

