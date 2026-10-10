# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_server::hocon_value' do
  it { is_expected.to run.with_params('TLSv1.3').and_return('"TLSv1.3"') }
  it { is_expected.to run.with_params('a "quoted" \\ path').and_return('"a \\"quoted\\" \\\\ path"') }
  it { is_expected.to run.with_params(60_000).and_return('60000') }
  it { is_expected.to run.with_params(1.5).and_return('1.5') }
  it { is_expected.to run.with_params(true).and_return('true') }
  it { is_expected.to run.with_params(['TLSv1.3', 'TLSv1.2']).and_return('["TLSv1.3", "TLSv1.2"]') }
  it { is_expected.to run.with_params([1, false]).and_return('[1, false]') }
end
