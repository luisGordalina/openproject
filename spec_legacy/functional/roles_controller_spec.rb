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
require_relative '../legacy_spec_helper'
require 'roles_controller'

describe RolesController, type: :controller do
  render_views

  fixtures :all

  before do
    User.current = nil
    session[:user_id] = 1 # admin
  end

  it 'destroys' do
    r = Role.new(name: 'ToBeDestroyed', permissions: [:view_wiki_pages])
    assert r.save

    delete :destroy, params: { id: r }
    assert_redirected_to roles_path
    assert_nil Role.find_by(id: r.id)
  end

  it 'destroys role in use' do
    delete :destroy, params: { id: 1 }
    assert_redirected_to roles_path
    assert flash[:error] == 'This role is in use and cannot be deleted.'
    refute_nil Role.find_by(id: 1)
  end

  it 'gets report' do
    get :report
    assert_response :success
    assert_template 'report'

    refute_nil assigns(:roles)
    assert_equal Role.order(Arel.sql('builtin, position')), assigns(:roles)

    assert_select 'input', attributes: { type: 'checkbox',
                                         name: 'permissions[3][]',
                                         value: 'add_work_packages',
                                         checked: 'checked' }

    assert_select 'input', attributes: { type: 'checkbox',
                                         name: 'permissions[3][]',
                                         value: 'delete_work_packages',
                                         checked: nil }
  end
end
