#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2022 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require 'spec_helper'
require 'webmock/rspec'

describe ::OAuthClients::ConnectionManager, type: :model do
  let(:user) { create :user }
  let(:host) { "http://example.org" }
  let(:provider_type) { ::Storages::Storage::PROVIDER_TYPE_NEXTCLOUD }
  let(:storage) { create(:storage, provider_type:, host: "#{host}/") }
  let(:scope) { [:all] } # OAuth2 resources to access, specific to provider
  let(:oauth_client) do
    create(:oauth_client,
           client_id: "nwz34rWsolvJvchfQ1bVHXfMb1ETK89lCBgzrLhWx3ACW5nKfmdcyf5ftlCyKGbk",
           client_secret: "A08n6CRBOOr41iqkWRynnP6BbmEnau7LeP9t9xrIbiYX46iXgmIZgqhJoDFjUMEq",
           integration: storage)
  end
  let(:oauth_client_token) { create(:oauth_client_token, oauth_client:, user:) }
  let(:instance) { described_class.new(user:, oauth_client:) }

  # Test the redirect_to_oauth_authorize function that puts together
  # the OAuth2 provider URL (Nextcloud) according to RFC specs.
  describe '#redirect_to_oauth_authorize' do
    let(:scope) { nil }
    let(:state) { nil }

    subject { instance.redirect_to_oauth_authorize(scope:, state:) }

    context 'with empty state and scope' do
      it 'returns the redirect URL' do
        expect(subject).to be_a String
        expect(subject).to include oauth_client.integration.host
        expect(subject).not_to include "scope"
        expect(subject).not_to include "state"
      end
    end

    context 'with state but empty scope' do
      let(:state) { "https://example.com/page" }

      it 'returns the redirect URL' do
        expect(subject).to be_a String
        expect(subject).to include oauth_client.integration.host
        expect(subject).not_to include "scope"
        expect(subject).to include "&state=https"
      end
    end

    context 'with multiple scopes but empty state' do
      let(:scope) { %i(email profile) }

      it 'returns the redirect URL' do
        expect(subject).to be_a String
        expect(subject).to include oauth_client.integration.host
        expect(subject).not_to include "state"
        expect(subject).to include "&scope=email%20profile"
      end
    end
  end

  # The first step in the OAuth2 flow is to produce a URL for the
  # user to authenticate and authorize access at the OAuth2 provider
  # (Nextcloud).
  describe '#get_access_token' do
    subject { instance.get_access_token }

    context 'with no OAuthClientToken present' do
      it 'returns a redirection URL' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_a String
        # Details of string are tested above in section #redirect_to_oauth_authorize
      end
    end

    context 'with no OAuthClientToken present and state parameters' do
      subject { instance.get_access_token(state: "some_state", scope: [:email]) }

      it 'returns the redirect URL' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_a String
        expect(subject.result).to include oauth_client.integration.host
        expect(subject.result).to include "&state=some_state"
        expect(subject.result).to include "&scope=email"
      end
    end

    context 'with an OAuthClientToken present' do
      before do
        oauth_client_token
      end

      it 'returns the OAuthClientToken' do
        expect(subject).to be_truthy
        expect(subject.result).to be_a OAuthClientToken # The one and only...
        expect(subject.result).to eql oauth_client_token
      end
    end
  end

  # In the second step the Authorization Server (Nextcloud) redirects
  # to a "callback" endpoint on the OAuth2 client (OpenProject):
  # http://<openproject>:4200/oauth_clients/8/callback?state=&code=7kRGJ...jG3KZ
  # This callback code basically just calls code_to_token(code).
  # The callback endpoint calls code_to_token(code) with the code
  # received and exchanges the code for a bearer+refresh token
  # using a HTTP request.
  describe '#code_to_token' do
    let(:code) { "7kRGJ...jG3KZ" }

    subject { instance.code_to_token(code) }

    context 'with happy path' do
      before do
        # Simulate a successful authorization returning the tokens
        response_body = {
          access_token: "yjTDZ...RYvRH",
          token_type: "Bearer",
          expires_in: 3600,
          refresh_token: "UwFp...1FROJ",
          user_id: "admin"
        }.to_json
        stub_request(:any, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 200, body: response_body)
      end

      it 'returns a valid ClientToken object', webmock: true do
        expect(subject.success).to be_truthy
        expect(subject.result).to be_a OAuthClientToken
      end
    end

    context 'with known reply invalid_request', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 400, body: { error: "invalid_request" }.to_json)
      end

      it 'returns a specific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.rack_oauth2.invalid_request')
        expect(subject.errors[:base].first).not_to include I18n.t('oauth_client.errors.oauth_returned_error')
      end
    end

    context 'with unknown reply', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 400, body: { error: "invalid_requesttt" }.to_json)
      end

      it 'returns an unspecific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.oauth_returned_error')
      end
    end

    context 'with reply including JSON syntax error', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(
            status: 400,
            headers: { 'Content-Type' => 'application/json; charset=utf-8' },
            body: "some: very, invalid> <json}"
          )
      end

      it 'returns an unspecific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.oauth_returned_error')
      end
    end

    context 'with 500 reply without body', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 500)
      end

      it 'returns an unspecific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.oauth_returned_error')
      end
    end

    context 'with bad HTTP response', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token')).to_raise(Net::HTTPBadResponse)
      end

      it 'returns an unspecific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.oauth_returned_http_error')
      end
    end

    context 'with timeout returns internal error', webmock: true do
      before do
        stub_request(:post, File.join(host, '/apps/oauth2/api/v1/token')).to_timeout
      end

      it 'returns an unspecific error message' do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors[:base].count).to be(1)
        expect(subject.errors[:base].first).to include I18n.t('oauth_client.errors.oauth_returned_standard_error')
      end
    end
  end

  describe '#refresh_token' do
    subject { instance.refresh_token }

    context 'without preexisting OAuthClientToken' do
      it 'returns an error message' do
        expect(subject.success).to be_falsey
        expect(subject.errors[:base].first)
          .to include I18n.t('oauth_client.errors.refresh_token_called_without_existing_token')
      end
    end

    context 'with successful response from OAuth2 provider (happy path)' do
      before do
        # Simulate a successful authorization returning the tokens
        response_body = {
          access_token: "xyjTDZ...RYvRH",
          token_type: "Bearer",
          expires_in: 3601,
          refresh_token: "xUwFp...1FROJ",
          user_id: "admin"
        }.to_json
        stub_request(:any, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 200, body: response_body)
        oauth_client_token
      end

      it 'returns a valid ClientToken object', webmock: true do
        expect(subject.success).to be_truthy
        expect(subject.result).to be_a OAuthClientToken
        expect(subject.result.access_token).to eq("xyjTDZ...RYvRH")
        expect(subject.result.refresh_token).to eq("xUwFp...1FROJ")
        expect(subject.result.expires_in).to be(3601)
      end
    end

    context 'with invalid access_token data' do
      before do
        # Simulate a token too long
        response_body = {
          access_token: "x" * 257, # will fail model validation
          token_type: "Bearer",
          expires_in: 3601,
          refresh_token: "xUwFp...1FROJ",
          user_id: "admin"
        }.to_json
        stub_request(:any, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 200, body: response_body)

        oauth_client_token
      end

      it 'returns dependent error from model validation', webmock: true do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors.size).to be(1)
        puts subject.errors
      end
    end

    context 'with server error from OAuth2 provider' do
      before do
        stub_request(:any, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_return(status: 400, body: { error: "invalid_request" }.to_json)
        oauth_client_token
      end

      it 'returns a server error', webmock: true do
        expect(subject.success).to be_falsey
        expect(subject.errors.size).to be(1)
        puts subject.errors
      end
    end

    context 'with successful response but invalid data' do
      before do
        # Simulate timeout
        stub_request(:any, File.join(host, '/apps/oauth2/api/v1/token'))
          .to_timeout
        oauth_client_token
      end

      it 'returns a valid ClientToken object', webmock: true do
        expect(subject.success).to be_falsey
        expect(subject.result).to be_nil
        expect(subject.errors.size).to be(1)
      end
    end
  end
end
