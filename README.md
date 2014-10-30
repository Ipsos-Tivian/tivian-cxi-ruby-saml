# Ruby SAML [![Build Status](https://secure.travis-ci.org/onelogin/ruby-saml.png)](http://travis-ci.org/onelogin/ruby-saml)

## Updating from 0.7.x to 0.8.x
Version `0.8.x` changes the namespace of the gem from `OneLogin::Saml` to `OneLogin::RubySaml`.  Please update your implementations of the gem accordingly.

## Overview

The Ruby SAML library is for implementing the client side of a SAML authorization, i.e. it provides a means for managing authorization initialization and confirmation requests from identity providers.

SAML authorization is a two step process and you are expected to implement support for both.

## Getting Started
In order to use the toolkit you will need to install the gem (either manually or using Bundler), and require the library in your Ruby application:

Using `Gemfile`

```ruby
# latest stable
gem 'ruby-saml', '~> 0.8.1'

# or track master for bleeding-edge
gem 'ruby-saml', :github => 'onelogin/ruby-saml'
```

Using Bundler

```sh
gem install ruby-saml
```

When requiring the gem, you can add the whole toolkit
```ruby
require 'onelogin/ruby-saml'
```

or just the required components individually:

```ruby
require 'onelogin/ruby-saml/authrequest'
```

## The Initialization Phase

This is the first request you will get from the identity provider. It will hit your application at a specific URL (that you've announced as being your SAML initialization point). The response to this initialization, is a redirect back to the identity provider, which can look something like this (ignore the saml_settings method call for now):

```ruby
def init
  request = OneLogin::RubySaml::Authrequest.new
  redirect_to(request.create(saml_settings))
end
```

Once you've redirected back to the identity provider, it will ensure that the user has been authorized and redirect back to your application for final consumption, this is can look something like this (the authorize_success and authorize_failure methods are specific to your application):

```ruby
def consume
  response          = OneLogin::RubySaml::Response.new(params[:SAMLResponse])
  response.settings = saml_settings

  if response.is_valid? && user = current_account.users.find_by_email(response.name_id)
    authorize_success(user)
  else
    authorize_failure(user)
  end
end
```

In the above there are a few assumptions in place, one being that the response.name_id is an email address. This is all handled with how you specify the settings that are in play via the saml_settings method. That could be implemented along the lines of this:

```ruby
def saml_settings
  settings = OneLogin::RubySaml::Settings.new

  settings.assertion_consumer_service_url = "http://#{request.host}/saml/finalize"
  settings.issuer                         = request.host
  settings.idp_sso_target_url             = "https://app.onelogin.com/trust/saml2/http-post/sso/#{OneLoginAppId}"
  settings.idp_cert_fingerprint           = OneLoginAppCertFingerPrint
  settings.name_identifier_format         = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"

  # Optional for most SAML IdPs
  settings.authn_context = "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport"

  settings
end
```

What's left at this point, is to wrap it all up in a controller and point the initialization and consumption URLs in OneLogin at that. A full controller example could look like this:

```ruby
# This controller expects you to use the URLs /saml/init and /saml/consume in your OneLogin application.
class SamlController < ApplicationController
  def init
    request = OneLogin::RubySaml::Authrequest.new
    redirect_to(request.create(saml_settings))
  end

  def consume
    response          = OneLogin::RubySaml::Response.new(params[:SAMLResponse])
    response.settings = saml_settings

    if response.is_valid? && user = current_account.users.find_by_email(response.name_id)
      authorize_success(user)
    else
      authorize_failure(user)
    end
  end

  private

  def saml_settings
    settings = OneLogin::RubySaml::Settings.new

    settings.assertion_consumer_service_url = "http://#{request.host}/saml/consume"
    settings.issuer                         = request.host
    settings.idp_sso_target_url             = "https://app.onelogin.com/saml/signon/#{OneLoginAppId}"
    settings.idp_cert_fingerprint           = OneLoginAppCertFingerPrint
    settings.name_identifier_format         = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"

    # Optional for most SAML IdPs
    settings.authn_context = "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport"

    # Optional. Describe according to IdP specification (if supported) which attributes the SP desires to receive in SAMLResponse.
    settings.attributes_index = 30

    settings
  end
end
```
## Metadata Based Configuration

The method above requires a little extra work to manually specify attributes about the IdP.  (And your SP application)  There's an easier method -- use a metadata exchange.  Metadata is just an XML file that defines the capabilities of both the IdP and the SP application.  It also contains the X.509 public
key certificates which add to the trusted relationship.  The IdP administrator can also configure custom settings for an SP based on the metadata.

Using ```idp_metadata_parser.parse_remote``` IdP metadata will be added to the settings withouth further ado.

```ruby
def saml_settings

  idp_metadata_parser = OneLogin::RubySaml::IdpMetadataParser.new
  # Returns OneLogin::RubySaml::Settings prepopulated with idp metadata
  settings = idp_metadata_parser.parse_remote("https://example.com/auth/saml2/idp/metadata")

  settings.assertion_consumer_service_url = "http://#{request.host}/saml/consume"
  settings.issuer                         = request.host
  settings.name_identifier_format         = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
  # Optional for most SAML IdPs
  settings.authn_context = "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport"

  settings
end
```
The following attributes are set:
  * id_sso_target_url
  * idp_slo_target_url
  * id_cert_fingerpint

If are using saml:AttributeStatement to transfer metadata, like the user name, you can access all the attributes through response.attributes. It contains all the saml:AttributeStatement with its 'Name' as a indifferent key and the one saml:AttributeValue as value.

```ruby
response          = OneLogin::RubySaml::Response.new(params[:SAMLResponse])
response.settings = saml_settings

response.attributes[:username]
```

Imagine this saml:AttributeStatement

```xml
  <saml:AttributeStatement>
    <saml:Attribute Name="uid">
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">demo</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name="another_value">
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">value1</saml:AttributeValue>
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">value2</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name="role">
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">role1</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name="role">
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">role2</saml:AttributeValue>
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">role3</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name="attribute_with_nil_value">
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>
    </saml:Attribute>
    <saml:Attribute Name="attribute_with_nils_and_empty_strings">
      <saml:AttributeValue/>
      <saml:AttributeValue>valuePresent</saml:AttributeValue>
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>
      <saml:AttributeValue xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="1"/>
    </saml:Attribute>
  </saml:AttributeStatement>
```

```ruby
pp(response.attributes)   # is an OneLogin::RubySaml::Attributes object
# => @attributes=
  {"uid"=>["demo"],
   "another_value"=>["value1", "value2"],
   "role"=>["role1", "role2", "role3"],
   "attribute_with_nil_value"=>[nil],
   "attribute_with_nils_and_empty_strings"=>["", "valuePresent", nil, nil]}>

# Active single_value_compatibility
OneLogin::RubySaml::Attributes.single_value_compatibility = true

pp(response.attributes[:uid])
# => "demo"

pp(response.attributes[:role])
# => "role1"

pp(response.attributes.single(:role))
# => "role1"

pp(response.attributes.multi(:role))
# => ["role1", "role2", "role3"]

pp(response.attributes[:attribute_with_nil_value])
# => nil

pp(response.attributes[:attribute_with_nils_and_empty_strings])
# => ""

pp(response.attributes[:not_exists])
# => nil

pp(response.attributes.single(:not_exists))
# => nil

pp(response.attributes.multi(:not_exists))
# => nil

# Deactive single_value_compatibility
OneLogin::RubySaml::Attributes.single_value_compatibility = false

pp(response.attributes[:uid])
# => ["demo"]

pp(response.attributes[:role])
# => ["role1", "role2", "role3"]

pp(response.attributes.single(:role))
# => "role1"

pp(response.attributes.multi(:role))
# => ["role1", "role2", "role3"]

pp(response.attributes[:attribute_with_nil_value])
# => [nil]

pp(response.attributes[:attribute_with_nils_and_empty_strings])
# => ["", "valuePresent", nil, nil]

pp(response.attributes[:not_exists])
# => nil

pp(response.attributes.single(:not_exists))
# => nil

pp(response.attributes.multi(:not_exists))
# => nil
```

## Service Provider Metadata

To form a trusted pair relationship with the IdP, the SP (you) need to provide metadata XML
to the IdP for various good reasons.  (Caching, certificate lookups, relaying party permissions, etc)

The class `OneLogin::RubySaml::Metadata` takes care of this by reading the Settings and returning XML.  All you have to do is add a controller to return the data, then give this URL to the IdP administrator.

The metdata will be polled by the IdP every few minutes, so updating your settings should propagate
to the IdP settings.

```ruby
class SamlController < ApplicationController
  # ... the rest of your controller definitions ...
  def metadata
    settings = Account.get_saml_settings
    meta = OneLogin::RubySaml::Metadata.new
    render :xml => meta.generate(settings), :content_type => "application/samlmetadata+xml"
  end
end
```

## Clock Drift

Server clocks tend to drift naturally. If during validation of the response you get the error "Current time is earlier than NotBefore condition" then this may be due to clock differences between your system and that of the Identity Provider.

First, ensure that both systems synchronize their clocks, using for example the industry standard [Network Time Protocol (NTP)](http://en.wikipedia.org/wiki/Network_Time_Protocol).

Even then you may experience intermittent issues though, because the clock of the Identity Provider may drift slightly ahead of your system clocks. To allow for a small amount of clock drift you can initialize the response passing in an option named `:allowed_clock_drift`. Its value must be given in a number (and/or fraction) of seconds. The value given is added to the current time at which the response is validated before it's tested against the `NotBefore` assertion. For example:

```ruby
response = OneLogin::RubySaml::Response.new(params[:SAMLResponse], :allowed_clock_drift => 1)
```

Make sure to keep the value as comfortably small as possible to keep security risks to a minimum.

## Adding Features, Pull Requests

* Fork the repository
* Make your feature addition or bug fix
* Add tests for your new features. This is important so we don't break any features in a future version unintentionally.
* Ensure all tests pass.
* Do not change rakefile, version, or history.
* Open a pull request, following [this template](https://gist.github.com/Lordnibbler/11002759).
