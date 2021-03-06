require 'spec_helper'

describe 'Datasets' do

  let(:lists_category) { FactoryGirl.create(:category, title: 'lists') }

  let!(:quality_dataset) { FactoryGirl.create(:dataset_description, en_title: 'doctors', category: lists_category, is_active: true, with_dataset: true, bad_quality: false) }

  context 'anonymous user' do
    let!(:not_quality_dataset) { FactoryGirl.create(:dataset_description, en_title: 'students', category: lists_category, is_active: true, with_dataset: true, bad_quality: true) }
    let!(:not_active_dataset) { FactoryGirl.create(:dataset_description, en_title: 'schools', category: lists_category, is_active: false, with_dataset: true, bad_quality: true) }

    it 'is able to all available datasets' do
      visit datasets_path(locale: :en)

      page.should have_content 'lists'

      page_have_datasets_in_category(lists_category, ['doctors'])
      page.should_not have_content('schools')
    end

    it 'is able to display also datasets with bad quality' do
      visit datasets_path(locale: :en)

      click_link 'All datasets'

      page.should have_content 'lists'

      page_have_datasets_in_category(lists_category, ['doctors', 'students'])
      page.should_not have_content('schools')
    end

    it 'is able to see similar dataset in dataset detail' do
      quality_dataset.similar_dataset_descriptions << not_quality_dataset
      quality_dataset.save!

      visit dataset_path(id: quality_dataset, locale: :en)

      page.should have_content 'students'
    end

    it 'is able to see published records and visible columns in dataset' do
      FactoryGirl.create(:field_description, en_title: 'First name', identifier: 'first_name', dataset_description: quality_dataset)
      FactoryGirl.create(:field_description, en_title: 'Last name', identifier: 'last_name', dataset_description: quality_dataset, is_visible_in_detail: false)
      FactoryGirl.create(:field_description, en_title: 'Description', identifier: 'description', dataset_description: quality_dataset, is_visible_in_listing: false)

      record_1 = quality_dataset.dataset_model.create!(first_name: 'John', last_name: 'Smith', description: 'Young', record_status: Dataset::RecordStatus.find(:published), quality_status: 'unclear')
      record_2 = quality_dataset.dataset_model.create!(first_name: 'Ann', last_name: 'Brutal', description: 'From city', record_status: Dataset::RecordStatus.find(:loaded))

      visit datasets_path(locale: :en)

      click_link 'doctors'

      page_should_have_content_with 'John', 'Smith'
      page_should_not_have_content_with 'Ann', 'Brutal', 'Young', 'From city'

      within("#kernel_ds_doctor_#{record_1.id}") do
        click_link 'View', match: :first
      end

      page_should_have_content_with 'John', 'Young', 'Unclear'
      page_should_not_have_content_with 'Smith'

      # metadata
      page.should have_content 'Published'
    end

    it 'is able to sort records by column with pagination' do
      FactoryGirl.create(:field_description, en_title: 'First name', identifier: 'first_name', dataset_description: quality_dataset)

      100.times do |index|
        quality_dataset.dataset_model.create!(:first_name => "Xavier#{index}", record_status: Dataset::RecordStatus.find(:published))
      end

      visit dataset_path(id: quality_dataset, locale: :en)

      click_link 'First name'
      page.should have_content 'Xavier1'

      click_link 'First name'
      page.should have_content 'Xavier99'
    end
  end

  context 'admin user' do
    before(:each) do
      generate_all_quality_status
      login_as(admin_user)
    end

    it 'is able to filter records', js: true do
      FactoryGirl.create(:field_description, en_title: 'First name', identifier: 'first_name', dataset_description: quality_dataset)

      quality_dataset.dataset_model.create!(first_name: 'John', record_status: Dataset::RecordStatus.find(:published), quality_status: 'unclear')
      quality_dataset.dataset_model.create!(first_name: 'Ann', record_status: Dataset::RecordStatus.find(:loaded), quality_status: 'ok')

      visit dataset_path(id: quality_dataset, locale: :en)

      page_should_have_content_with 'John', 'Ann'

      select 'Loaded', from: 'filters_record_status', match: :first

      page.should have_content 'Ann'
      page.should_not have_content 'John'

      select '- All -', from: 'filters_record_status', match: :first
      page.should have_content 'John'
      page.should have_content 'Ann'

      select 'Unclear', from: 'filters_quality_status', match: :first
      page.should have_content 'John'
      page.should_not have_content 'Ann'
    end

    it 'is able to update record status and quality status for multiple rows at once', js: true do
      FactoryGirl.create(:field_description, en_title: 'First name', identifier: 'first_name', dataset_description: quality_dataset)

      record_1 = quality_dataset.dataset_model.create!(first_name: 'John', record_status: Dataset::RecordStatus.find(:published), quality_status: 'unclear')
      record_2 = quality_dataset.dataset_model.create!(first_name: 'Ann', record_status: Dataset::RecordStatus.find(:loaded), quality_status: 'ok')
      record_3 = quality_dataset.dataset_model.create!(first_name: 'Peter', record_status: Dataset::RecordStatus.find(:new), quality_status: 'absent')

      visit dataset_path(id: quality_dataset, locale: :en)

      check "check_kernel_ds_doctor_#{record_1._record_id}"
      check "check_kernel_ds_doctor_#{record_3._record_id}"
      page.should have_select 'status'
      select 'Suspended', from: 'status'

      page.should have_xpath '//img[@alt="Suspended"]'
      record_1.reload.record_status.should eq 'suspended'
      record_2.reload.record_status.should eq 'loaded'
      record_3.reload.record_status.should eq 'suspended'

      check "check_kernel_ds_doctor_#{record_1._record_id}"
      check "check_kernel_ds_doctor_#{record_2._record_id}"
      page.should have_select 'quality'
      select 'Duplicate', from: 'quality'

      page.should have_xpath '//img[@alt="Duplicate"]'
      record_1.reload.quality_status.should eq 'duplicate'
      record_2.reload.quality_status.should eq 'duplicate'
      record_3.reload.quality_status.should eq 'absent'

      check "check_kernel_ds_doctor_#{record_1._record_id}"
      select 'All filtered records', from: 'selection'
      page.should have_select 'status'
      select 'New', from: 'status'

      page.should have_xpath '//img[@alt="New"]'
      record_1.reload.record_status.should eq 'new'
      record_2.reload.record_status.should eq 'new'
      record_3.reload.record_status.should eq 'new'

      check 'select_all_records'
      page.should have_select 'quality'
      select 'OK', from: 'quality'

      page.should have_xpath '//img[@alt="OK"]'
      record_1.reload.quality_status.should eq 'ok'
      record_2.reload.quality_status.should eq 'ok'
      record_3.reload.quality_status.should eq 'ok'
    end

    it 'is able to use batch update to set the same value for multiple records at once', js: true do
      FactoryGirl.create(:field_description, en_title: 'First name', identifier: 'first_name', dataset_description: quality_dataset)
      FactoryGirl.create(:field_description, en_title: 'Last name', identifier: 'last_name', dataset_description: quality_dataset)

      record_1 = quality_dataset.dataset_model.create!(first_name: 'John', last_name: 'Smith')
      record_2 = quality_dataset.dataset_model.create!(first_name: 'Ann', last_name: 'Hamster')
      record_3 = quality_dataset.dataset_model.create!(first_name: 'Peter', last_name: 'House')

      visit dataset_path(id: quality_dataset, locale: :en)

      check "check_kernel_ds_doctor_#{record_1._record_id}"
      check "check_kernel_ds_doctor_#{record_3._record_id}"
      click_link 'Batch edit'

      page.should have_content 'Editing 2 selected records'

      fill_in 'value_last_name', with: 'Bob'
      click_button 'Update all'

      page.should have_content '2 records were successfuly updated'

      record_1.reload.first_name.should eq 'John'
      record_1.reload.last_name.should eq 'Bob'

      record_2.reload.first_name.should eq 'Ann'
      record_2.reload.last_name.should eq 'Hamster'

      record_3.reload.first_name.should eq 'Peter'
      record_3.reload.last_name.should eq 'Bob'
    end

    it 'should not fail when user make batch edit with no new value'
  end

  private

  def page_have_datasets_in_category(category, dateset_names)
    within(".dataset_category_#{category.id}") do
      page_should_have_content_with *dateset_names
    end
  end

end
