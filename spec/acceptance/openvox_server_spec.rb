# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'openvox_server' do
  context 'with defaults' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { "class { 'openvox_server': }" }
    end
  end
end
