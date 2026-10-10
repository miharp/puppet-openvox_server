# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_server::package_version' do
  it { is_expected.to run.with_params('present', 'el9', 'RedHat').and_return('present') }
  it { is_expected.to run.with_params('installed', 'debian12', 'Debian').and_return('installed') }
  it { is_expected.to run.with_params('latest', 'el9', 'RedHat').and_return('latest') }
  it { is_expected.to run.with_params('9.0.1', 'el9', 'RedHat').and_return('9.0.1-1.el9') }
  it { is_expected.to run.with_params('9.0.1', 'debian12', 'Debian').and_return('9.0.1-1+debian12') }
  it { is_expected.to run.with_params('9.0.1', 'ubuntu24.04', 'Debian').and_return('9.0.1-1+ubuntu24.04') }
  it { is_expected.to run.with_params('9.0.0~rc4-1+debian12', 'debian12', 'Debian').and_return('9.0.0~rc4-1+debian12') }
  it { is_expected.to run.with_params('8.8.1-2.el9', 'el9', 'RedHat').and_return('8.8.1-2.el9') }
end
