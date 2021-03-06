require 'spec_helper'

describe Project do
  it { should_not have_valid(:owner_id).when('', nil) }

  context 'name validation' do
    it 'accepts letter, digits, underscores and hyphens' do
      should have_valid(:name).when('KanbanRoots')
      should have_valid(:name).when('Kanban-roots')
      should have_valid(:name).when('Kanban_roots')
      should have_valid(:name).when('Kanban-roots_11')
    end

    it 'denies blanks' do
      should_not have_valid(:name).when('', nil)
    end

    it 'denies whitespaces' do
      should_not have_valid(:name).when('kanban roots')
    end

    it 'denies symbols' do
      should_not have_valid(:name).when(
        *%w(a! a@ a# a$ a% a" a& a* a( a) a+ a= a{ a[ a} a] a? a/ a| a\ a' a"))
    end

    it 'converts to downcase when saving' do
      project = Factory.create :project, :name => 'KAnBaN-RootS'
      project.name.should == 'kanban-roots'
      project.name = 'ROOTS_OF-KANBAN'
      project.save!
      project.name.should == 'roots_of-kanban'
    end

    it 'validates uniqueness for contributor' do
      contributor = Factory.create :contributor
      Factory.create :project, :name => 'kanban-roots', :owner => contributor
      expect {
        Factory.create :project, :name => 'kanban-roots', :owner => contributor
      }.to raise_error ActiveRecord::RecordInvalid

      contributor2 = Factory.create :contributor
      expect {
        Factory.create :project, :name => 'kanban-roots', :owner => contributor2
      }.to_not raise_error
    end
  end

  it 'should return all contributors, including owner and other contributors' do
    hugo = Factory.create :contributor
    rodrigo = Factory.create :contributor
    dudu = Factory.create :contributor
    project = Factory.create :project, :owner => hugo, :contributors => [rodrigo]
    project.all_contributors.should include(hugo, rodrigo)
    project.all_contributors.should_not include(dudu)
  end

  it 'should return a json with its contributors id and name' do
    hugo = Factory.create :contributor, :name => 'Hugo'
    rodrigo = Factory.create :contributor, :name => 'Rodrigo'
    project = Factory.create :project, :contributors => [hugo, rodrigo]
    json = '[{"id":1,"name":"Hugo"},{"id":2,"name":"Rodrigo"}]'
    project.contributors_for_token_input.should == json
  end

  it 'should set the contributor_ids given a ids string splited by commas' do
    hugo = Factory.create :contributor, :name => 'Hugo'
    rodrigo = Factory.create :contributor, :name => 'Rodrigo'
    project = Factory.create :project
    project.contributor_tokens = "#{hugo.id}, #{rodrigo.id}"
    project.contributor_ids.should include(hugo.id, rodrigo.id)
    project.contributor_ids.should have(2).ids
  end

  it 'returns all related tasks matching a given position' do
    tasks = [stub_model(Task, :position => 1),
             stub_model(Task, :position => 1),
             stub_model(Task, :position => 2),
             stub_model(Task, :position => 3),
             stub_model(Task, :position => 3)]
    project = Project.new
    project.tasks.<<(*tasks)

    project.should have(2).tasks_by_position(1)
    project.tasks_by_position(1).should include(*tasks[0..1])

    project.tasks_by_position(2).should == [tasks[2]]

    project.should have(2).tasks_by_position(3)
    project.tasks_by_position(3).should include(*tasks[3..4])

    project.tasks_by_position(4).should be_empty
  end

  it 'cleanup all Done tasks' do
    tasks = [stub_model(Task, :position => Board::POSITIONS['doing']),
             stub_model(Task, :position => Board::POSITIONS['done']),
             stub_model(Task, :position => Board::POSITIONS['done']),
             stub_model(Task, :position => Board::POSITIONS['done']),
             stub_model(Task, :position => Board::POSITIONS['done'])]
    project = Project.new
    project.tasks.<<(*tasks)

    project.clean_up_done_tasks
    done_tasks = project.tasks.select {|item| item.position == Board::POSITIONS['done'] }
    done_tasks.should be_empty

    out_tasks = project.tasks.select {|item| item.position == Board::POSITIONS['out'] }
    out_tasks.should include(*tasks[1..4])
    out_tasks.should have(4).tasks
  end

  it 'returns the task points sum for a given position of the board' do
    tasks = [stub_model(Task, :points => 1, :position => Board::POSITIONS['doing']),
             stub_model(Task, :points => 2, :position => Board::POSITIONS['doing']),
             stub_model(Task, :points => 8, :position => Board::POSITIONS['todo']),
             stub_model(Task, :points => nil, :position => Board::POSITIONS['todo']),
             stub_model(Task, :points => 3, :position => Board::POSITIONS['doing']),
             stub_model(Task, :points => 5, :position => Board::POSITIONS['todo'])]
    project = Project.new
    project.tasks.<<(*tasks)

    project.count_points(Board::POSITIONS['todo']).should == 13
    project.count_points(Board::POSITIONS['doing']).should == 6
    project.count_points(Board::POSITIONS['done']).should == 0
  end

  it 'should be sorted by name' do
    project_z = Factory.create :project, :name => 'Zoo'
    project_a = Factory.create :project, :name => 'Anything'
    project_b = Factory.create :project, :name => 'BatleField'

    projects = [project_b, project_z, project_a]
    projects.sort.should == [project_a, project_b, project_z]

    projects = [project_z, project_a, project_b]
    projects.sort.should == [project_a, project_b, project_z]
  end

  context 'contributors scores should be ordered by score' do
    it "should return a list of hashs {contributor, scores} ordered by scores" do
      dudu = Factory.create :contributor
      max = Factory.create :contributor
      hugo = Factory.create :contributor
      project = Factory.create :project, :owner => hugo, :contributors => [dudu, max]

      Factory.create :task, :project => project, :position => Board::POSITIONS['doing'], :contributors => [dudu], :points => 13
      Factory.create :task, :project => project, :position => Board::POSITIONS['todo'], :contributors => [hugo], :points => 5
      Factory.create :task, :project => project, :position => Board::POSITIONS['backlog'], :contributors => [max], :points => 8
      Factory.create :task, :project => project, :position => Board::POSITIONS['out'], :contributors => [dudu, hugo, max], :points => 1

      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [dudu], :points => 1
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo, dudu], :points => 3
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [max], :points => 2
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => 5
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [dudu, max], :points => 3
      project.update_attribute(:tasks, Task.all)

      project.contributors_scores.should == [{ :contributor => hugo, :scores => 8 },
                                             { :contributor => dudu, :scores => 7 },
                                             { :contributor => max, :scores =>  5}]

      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [max], :points => 13
      project.update_attribute(:tasks, Task.all)

      project.contributors_scores.should == [{ :contributor => max, :scores => 18 },
                                             { :contributor => hugo, :scores => 8 },
                                             { :contributor => dudu, :scores => 7}]
    end

    it 'should ignore taks without points' do
      hugo = Factory.create :contributor
      project = Factory.create :project, :owner => hugo

      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => nil
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => 3
      project.update_attribute(:tasks, Task.all)

      project.contributors_scores.should == [{ :contributor => hugo, :scores => 3 }]
    end

    it 'should sum 0.1 for taks with 0 points' do
      hugo = Factory.create :contributor
      project = Factory.create :project, :contributors => [hugo]

      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => 0
      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => 3
      project.update_attribute(:tasks, Task.all)

      project.contributors_scores[0][:scores].should == 3.1

      Factory.create :task, :project => project, :position => Board::POSITIONS['done'], :contributors => [hugo], :points => 0
      project.update_attribute(:tasks, Task.all)

      project.contributors_scores[0][:scores].should == 3.2
    end
  end

  it 'when delete a project, delete all its dependencies' do
    project = Factory.create :project
    task = Factory.create :task, :project => project
    comment = Factory.create :comment, :task => task
    category = Factory.create :category, :project => project

    project.destroy

    lambda { task.reload }.should raise_error(ActiveRecord::RecordNotFound)
    lambda { comment.reload }.should raise_error(ActiveRecord::RecordNotFound)
    lambda { category.reload }.should raise_error(ActiveRecord::RecordNotFound)
  end
end

