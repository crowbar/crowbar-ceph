#
# Copyright 2016, SUSE Linux GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Api::StoragesController < ApiController
  before_action :set_ceph

  api :GET, "/api/storages", "List all Ceph storages"
  api_version "2.0"
  def index
    render json: [], status: :not_implemented
  end

  api :GET, "/api/storages/:id", "Show a single Ceph storage"
  param :id, Integer, desc: "Ceph Storage ID", required: true
  api_version "2.0"
  def show
    render json: {}, status: :not_implemented
  end

  api :GET, "/api/storages/repocheck", "Sanity check ceph repositories"
  api_version "2.0"
  def repocheck
    render json: @ceph.repocheck
  end

  protected

  def set_ceph
    @ceph = Api::Storage.new
  end
end
