# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'openvox_server' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_class('openvox_server::install') }
      it { is_expected.to contain_class('openvox_server::config') }
      it { is_expected.to contain_class('openvox_server::service') }

      it 'install comes before config' do
        is_expected.to contain_class('openvox_server::install')
          .that_comes_before('Class[openvox_server::config]')
      end

      it 'config notifies service' do
        is_expected.to contain_class('openvox_server::config')
          .that_notifies('Class[openvox_server::service]')
      end

      context 'with manage_package => false' do
        let(:params) { { manage_package: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('openvox_server') }
      end

      context 'with manage_service => false' do
        let(:params) { { manage_service: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('openvox_server') }
      end
    end
  end
end
