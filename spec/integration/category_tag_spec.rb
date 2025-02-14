# encoding: UTF-8
# frozen_string_literal: true

require 'rails_helper'

describe "category tag restrictions" do

  def sorted_tag_names(tag_records)
    tag_records.map(&:name).sort
  end

  def filter_allowed_tags(opts = {})
    DiscourseTagging.filter_allowed_tags(Tag.all, Guardian.new(user), opts)
  end

  fab!(:tag1) { Fabricate(:tag, name: 'tag1') }
  fab!(:tag2) { Fabricate(:tag, name: 'tag2') }
  fab!(:tag3) { Fabricate(:tag, name: 'tag3') }
  fab!(:tag4) { Fabricate(:tag, name: 'tag4') }

  fab!(:user)  { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.min_trust_to_create_tag = 0
    SiteSetting.min_trust_level_to_tag_topics = 0
  end

  context "tags restricted to one category" do
    fab!(:category_with_tags) { Fabricate(:category) }
    fab!(:other_category)     { Fabricate(:category) }

    before do
      category_with_tags.tags = [tag1, tag2]
    end

    it "tags belonging to that category can only be used there" do
      post = create_post(category: category_with_tags, tags: [tag1.name, tag2.name, tag3.name])
      expect(post.topic.tags).to contain_exactly(tag1, tag2)

      post = create_post(category: other_category, tags: [tag1.name, tag2.name, tag3.name])
      expect(post.topic.tags).to contain_exactly(tag3)
    end

    it "search can show only permitted tags" do
      expect(filter_allowed_tags.count).to eq(Tag.count)
      expect(filter_allowed_tags(for_input: true, category: category_with_tags)).to contain_exactly(tag1, tag2)
      expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag3, tag4)
      expect(filter_allowed_tags(for_input: true, category: category_with_tags, selected_tags: [tag1.name])).to contain_exactly(tag2)
      expect(filter_allowed_tags(for_input: true, category: category_with_tags, selected_tags: [tag1.name], term: 'tag')).to contain_exactly(tag2)
      expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3, tag4)
      expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name])).to contain_exactly(tag4)
      expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name], term: 'tag')).to contain_exactly(tag4)
    end

    it "can't create new tags in a restricted category" do
      post = create_post(category: category_with_tags, tags: [tag1.name, "newtag"])
      expect(post.topic.tags).to contain_exactly(tag1)
      post = create_post(category: category_with_tags, tags: [tag1.name, "newtag"], user: admin)
      expect(post.topic.tags).to contain_exactly(tag1)
    end

    it "can create new tags in a non-restricted category" do
      post = create_post(category: other_category, tags: [tag3.name, "newtag"])
      expect(post.topic.tags.map(&:name).sort).to eq([tag3.name, "newtag"].sort)
    end

    it "can create tags when changing category settings" do
      expect { other_category.update(allowed_tags: ['newtag']) }.to change { Tag.count }.by(1)
      expect { other_category.update(allowed_tags: [tag1.name, 'tag-stuff', tag2.name, 'another-tag']) }.to change { Tag.count }.by(2)
    end

    context 'category allows other tags to be used' do
      before do
        category_with_tags.update!(allow_global_tags: true)
      end

      it "search can show the permitted tags" do
        expect(filter_allowed_tags.count).to eq(Tag.count)
        expect(filter_allowed_tags(for_input: true, category: category_with_tags)).to contain_exactly(tag1, tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: category_with_tags, selected_tags: [tag1.name])).to contain_exactly(tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: category_with_tags, selected_tags: [tag1.name], term: 'tag')).to contain_exactly(tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name])).to contain_exactly(tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name], term: 'tag')).to contain_exactly(tag4)
      end

      it "works if no tags are restricted to the category" do
        other_category.update!(allow_global_tags: true)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name])).to contain_exactly(tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category, selected_tags: [tag3.name], term: 'tag')).to contain_exactly(tag4)
      end
    end
  end

  context "tag groups restricted to a category" do
    fab!(:tag_group1)     { Fabricate(:tag_group) }
    fab!(:category)        { Fabricate(:category) }
    fab!(:other_category)  { Fabricate(:category) }

    before do
      tag_group1.tags = [tag1, tag2]
      category.allowed_tag_groups = [tag_group1.name]
      category.reload
    end

    it "tags in the group are used by category tag restrictions" do
      expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2)
      expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag3, tag4)

      tag_group1.tags = [tag2, tag3, tag4]
      expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag2, tag3, tag4)
      expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag1)
      expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag1)
    end

    it "groups and individual tags can be mixed" do
      category.allowed_tags = [tag4.name]
      category.reload

      expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag4)
      expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag3)
      expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3)
    end

    it "enforces restrictions when creating a topic" do
      post = create_post(category: category, tags: [tag1.name, "newtag"])
      expect(post.topic.tags.map(&:name)).to eq([tag1.name])
    end

    context 'category allows other tags to be used' do
      before do
        category.update!(allow_global_tags: true)
      end

      it 'filters tags correctly' do
        expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3, tag4)

        tag_group1.tags = [tag2, tag3, tag4]
        expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag1)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag1)
      end

      it "works if no tags are restricted to the category" do
        other_category.update!(allow_global_tags: true)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag3, tag4)
        tag_group1.tags = [tag2, tag3, tag4]
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag1)
      end

      context 'another category has restricted tags using groups' do
        fab!(:category2) { Fabricate(:category) }
        fab!(:tag_group2) { Fabricate(:tag_group) }

        before do
          tag_group2.tags = [tag2, tag3]
          category2.allowed_tag_groups = [tag_group2.name]
          category2.reload
        end

        it 'filters tags correctly' do
          expect(filter_allowed_tags(for_input: true, category: category2)).to contain_exactly(tag2, tag3)
          expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag4)
        end

        it "doesn't care about tags in a group that isn't used in a category" do
          unused_tag_group = Fabricate(:tag_group)
          unused_tag_group.tags = [tag4]
          expect(filter_allowed_tags(for_input: true, category: category2)).to contain_exactly(tag2, tag3)
          expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag4)
        end
      end

      context 'another category has restricted tags' do
        fab!(:category2) { Fabricate(:category) }

        it "doesn't filter tags that are also restricted in another category" do
          category2.tags = [tag2, tag3]
          expect(filter_allowed_tags(for_input: true, category: category2)).to contain_exactly(tag2, tag3)
          expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag4)
          expect(filter_allowed_tags(for_input: true, category: category)).to contain_exactly(tag1, tag2, tag4)
        end
      end
    end
  end

  context "tag groups with parent tag" do
    it "for input field, filter_allowed_tags returns results based on whether parent tag is present or not" do
      tag_group = Fabricate(:tag_group, parent_tag_id: tag1.id)
      tag_group.tags = [tag3, tag4]
      expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag1, tag2)
      expect(filter_allowed_tags(for_input: true, selected_tags: [tag1.name])).to contain_exactly(tag2, tag3, tag4)
      expect(filter_allowed_tags(for_input: true, selected_tags: [tag1.name, tag3.name])).to contain_exactly(tag2, tag4)
    end

    it "for tagging a topic, filter_allowed_tags allows tags without parent tag" do
      tag_group = Fabricate(:tag_group, parent_tag_id: tag1.id)
      tag_group.tags = [tag3, tag4]
      expect(filter_allowed_tags(for_topic: true)).to contain_exactly(tag1, tag2, tag3, tag4)
      expect(filter_allowed_tags(for_topic: true, selected_tags: [tag1.name])).to contain_exactly(tag1, tag2, tag3, tag4)
      expect(filter_allowed_tags(for_topic: true, selected_tags: [tag1.name, tag3.name])).to contain_exactly(tag1, tag2, tag3, tag4)
    end

    context "and category restrictions" do
      fab!(:car_category)    { Fabricate(:category) }
      fab!(:other_category)  { Fabricate(:category) }
      fab!(:makes)           { Fabricate(:tag_group, name: "Makes") }
      fab!(:honda_group)     { Fabricate(:tag_group, name: "Honda Models") }
      fab!(:ford_group)      { Fabricate(:tag_group, name: "Ford Models") }

      before do
        @tags = {}
        ['honda', 'ford', 'civic', 'accord', 'mustang', 'taurus'].each do |name|
          @tags[name] = Fabricate(:tag, name: name)
        end

        makes.tags = [@tags['honda'], @tags['ford']]

        honda_group.parent_tag_id = @tags['honda'].id
        honda_group.save
        honda_group.tags = [@tags['civic'], @tags['accord']]

        ford_group.parent_tag_id = @tags['ford'].id
        ford_group.save
        ford_group.tags = [@tags['mustang'], @tags['taurus']]

        car_category.allowed_tag_groups = [makes.name, honda_group.name, ford_group.name]
      end

      it "handles all those rules" do
        # car tags can't be used outside of car category:
        expect(filter_allowed_tags(for_input: true)).to contain_exactly(tag1, tag2, tag3, tag4)
        expect(filter_allowed_tags(for_input: true, category: other_category)).to contain_exactly(tag1, tag2, tag3, tag4)

        # in car category, a make tag must be given first:
        expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category))).to eq(['ford', 'honda'])

        # model tags depend on which make is chosen:
        expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['honda']))).to eq(['accord', 'civic', 'ford'])
        expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['ford']))).to eq(['honda', 'mustang', 'taurus'])
      end

      it "can apply the tags to a topic" do
        post = create_post(category: car_category, tags: ['ford', 'mustang'])
        expect(post.topic.tags.map(&:name).sort).to eq(['ford', 'mustang'])
      end

      context "limit one tag from each group" do
        before do
          makes.update(one_per_topic: true)
          honda_group.update(one_per_topic: true)
          ford_group.update(one_per_topic: true)
        end

        it "can restrict one tag from each group" do
          expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category))).to eq(['ford', 'honda'])
          expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['honda']))).to eq(['accord', 'civic'])
          expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['ford']))).to eq(['mustang', 'taurus'])
          expect(sorted_tag_names(filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['ford', 'mustang']))).to eq([])
        end

        it "can apply the tags to a topic" do
          post = create_post(category: car_category, tags: ['ford', 'mustang'])
          expect(post.topic.tags.map(&:name).sort).to eq(['ford', 'mustang'])
        end

        it "can remove extra tags from the same group" do
          # A weird case that input field wouldn't allow.
          # Only one tag from car makers is allowed, but we're saying that two have been selected.
          names = filter_allowed_tags(for_input: true, category: car_category, selected_tags: ['honda', 'ford']).map(&:name)
          expect(names.include?('honda') || names.include?('ford')).to eq(false)
          expect(names).to include('civic')
          expect(names).to include('mustang')
        end
      end
    end
  end
end

describe "tag topic counts per category" do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:category2) { Fabricate(:category) }
  fab!(:tag1) { Fabricate(:tag) }
  fab!(:tag2) { Fabricate(:tag) }
  fab!(:tag3) { Fabricate(:tag) }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.min_trust_to_create_tag = 0
    SiteSetting.min_trust_level_to_tag_topics = 0
  end

  it "counts when a topic is created with tags" do
    expect {
      Fabricate(:topic, category: category, tags: [tag1, tag2])
    }.to change { CategoryTagStat.count }.by(2)
    expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(1)
    expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(1)
  end

  it "counts when tag is added to an existing topic" do
    topic = Fabricate(:topic, category: category)
    post = Fabricate(:post, user: topic.user, topic: topic)
    expect(CategoryTagStat.where(category: category).count).to eq(0)
    expect {
      PostRevisor.new(post).revise!(topic.user, raw: post.raw, tags: [tag1.name, tag2.name])
    }.to change { CategoryTagStat.count }.by(2)
    expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(1)
    expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(1)
  end

  context "topic with 2 tags" do
    fab!(:topic) { Fabricate(:topic, category: category, tags: [tag1, tag2]) }
    fab!(:post)  { Fabricate(:post, user: topic.user, topic: topic) }

    it "has correct counts after tag is removed from a topic" do
      post
      topic2 = Fabricate(:topic, category: category, tags: [tag2])
      expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(2)
      PostRevisor.new(post).revise!(topic.user, raw: post.raw, tags: [])
      expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(1)
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(0)
    end

    it "has correct counts after a topic's category changes" do
      PostRevisor.new(post).revise!(topic.user, category_id: category2.id, raw: post.raw, tags: [tag1.name, tag2.name])
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category2, tag: tag1).sum(:topic_count)).to eq(1)
      expect(CategoryTagStat.where(category: category2, tag: tag2).sum(:topic_count)).to eq(1)
    end

    it "has correct counts after topic's category AND tags changed" do
      PostRevisor.new(post).revise!(topic.user, raw: post.raw, tags: [tag2.name, tag3.name], category_id: category2.id)
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category, tag: tag2).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category, tag: tag3).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category2, tag: tag1).sum(:topic_count)).to eq(0)
      expect(CategoryTagStat.where(category: category2, tag: tag2).sum(:topic_count)).to eq(1)
      expect(CategoryTagStat.where(category: category2, tag: tag3).sum(:topic_count)).to eq(1)
    end
  end

  context "topic with one tag" do
    fab!(:topic) { Fabricate(:topic, tags: [tag1], category: category) }
    fab!(:post) { Fabricate(:post, user: topic.user, topic: topic) }

    it "counts after topic becomes uncategorized" do
      PostRevisor.new(post).revise!(topic.user, raw: post.raw, tags: [tag1.name], category_id: SiteSetting.uncategorized_category_id)
      expect(CategoryTagStat.where(category: Category.find(SiteSetting.uncategorized_category_id), tag: tag1).sum(:topic_count)).to eq(1)
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(0)
    end

    it "updates counts after topic is deleted" do
      PostDestroyer.new(admin, post).destroy
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(0)
    end

    it "updates counts after topic is recovered" do
      PostDestroyer.new(admin, post).destroy
      PostDestroyer.new(admin, post).recover
      expect(CategoryTagStat.where(category: category, tag: tag1).sum(:topic_count)).to eq(1)
    end
  end
end
