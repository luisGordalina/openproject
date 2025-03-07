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
require 'rack/test'

describe 'API v3 Configuration resource', type: :request do
  include Rack::Test::Methods
  include ::API::V3::Utilities::PathHelper

  let(:user) { create(:user) }
  let(:configuration_path) { api_v3_paths.configuration }

  subject(:response) { last_response }

  before do
    login_as(user)
  end

  describe '#GET' do
    before do
      get configuration_path
    end

    it 'returns 200 OK' do
      expect(subject.status).to eq(200)
    end

    it 'returns the configuration', with_settings: { per_page_options: '3, 5, 8, 13' } do
      expect(subject.body)
        .to be_json_eql('Configuration'.to_json)
        .at_path("_type")

      expect(subject.body)
        .to be_json_eql([3, 5, 8, 13].to_json)
        .at_path('perPageOptions')
    end

    it 'embedds the current user preferences' do
      expect(subject.body)
        .to be_json_eql('UserPreferences'.to_json)
        .at_path('_embedded/userPreferences/_type')
    end

    context 'for a non logged in user' do
      it 'returns 200 OK' do
        expect(subject.status).to eq(200)
      end
    end

    it 'does not embed the preferences' do
      expect(subject.body)
        .not_to have_json_path('_embedded/user_preferences')
    end
  end
end
