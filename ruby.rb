#===============================================================================
#■ 覚醒スキル
# ソフト：RPGツクールVX Ace(RGSS3)
# Last Update：20**/**/**
# Current Version：***
#-------------------------------------------------------------------------------
#アクターが特定条件に達した時に使えるようにし、使うとなくなるスキルを追加します(予定)。
#===============================================================================
=begin

  戦闘開始時のみでもいい奴が何回も呼ばれているの重そう
  aliasの罠には気を付けよう
  class Scene_Battle の中の @log_window で戦闘メッセージが作れて最高


  <スキル:HP:300> or <スキル:HP:30%>
  <スキル:攻撃力:50> or <スキル:攻撃力:5倍>

=end
#///////////////////////////////////////////////////////////////////////////////
module User

  USE = 1

  MASTER_WORD = "スキル"

  LOG = "@nameは必殺技が使えるようになった"

  WAIT = 2

  W1_HP = "HP"

  W2_ATK = "攻撃力"

  W3_MAT = "魔法力"

  W4_CTL = "クリティカル"

  W5_MP = "MP"

end

module Skill_set
  # [ actor_id, skill_id, option]
  SET = [
    [1, 76],
    [2, 77]
  ]
end

class Scene_Battle

  alias battle_set battle_start
  def battle_start
    @status = {
      actor: [],
      enemy: []
    }

    for i in 0...$game_party.members.size do

      z = $game_party.members[i].id
      @status[:actor].push({
        id: z,
        max_hp: $game_actors[z].param(0),
        max_mp: $game_actors[z].param(1),
        hp: $game_actors[z].hp,
        mp: $game_actors[z].mp,
        attack: $game_actors[z].param(2),
        defense: $game_actors[z].param(3),
        magic: $game_actors[z].param(4),
        speed: $game_actors[z].param(6),
        luck: $game_actors[z].param(7),
        critical: [false, 0],
        use: User::USE,
        get?: false,
        log: User::LOG.clone
      })
    end

    for i in 0...$game_troop.members.size do
      @status[:enemy].push({
        id: $game_troop.members[i].enemy_id,
        max_hp: $game_troop.members[i].param(0),
        max_mp: $game_troop.members[i].param(1),
        hp: $game_troop.members[i].hp,
        mp: $game_troop.members[i].mp,
        attack: $game_troop.members[i].param(2),
        defense: $game_troop.members[i].param(3),
        magic: $game_troop.members[i].param(4),
        speed: $game_troop.members[i].param(6),
        luck: $game_troop.members[i].param(7),
        critical: [false, 0]
      })
    end
    battle_set
  end

  alias subject_log use_item
  def use_item
    subject_log

    hp_damage = 0
    target_id = []
    critical = [false, 0]

    targets = @subject.current_action.make_targets.compact
    targets.each {|target|
      if target.result.critical == true
        critical[1] += 1
      else
        critical[0] = critical[1] > 0 ? true : false
      end

      hp_damage += target.result.hp_damage
      target_id.push(target.index)
    }

    if @subject.actor?
      skill = @subject.current_action.item.is_a?(RPG::Skill) ? @subject.current_action.item.id : 0
      for i in 0...Skill_set::SET.length do
        if @status[:actor][@subject.index][:id] == Skill_set::SET[i][0]
          id = Skill_set::SET[i][1]
          break
        end
      end
      if skill == id
        @status[:actor][i][:use] -= 1
      end

      total_ctl = @status[:actor][@subject.index][:critical][1]
      @status[:actor][@subject.index].store(:hp, $game_actors[@status[:actor][@subject.index][:id]].hp)
      @status[:actor][@subject.index].store(:target, target_id)
      @status[:actor][@subject.index].store(:damage, hp_damage)
      @status[:actor][@subject.index].store(:critical, [critical[0], total_ctl + critical[1]])
    else
      total_ctl = @status[:enemy][@subject.index][:critical][1]
      @status[:enemy][@subject.index].store(:hp, $game_troop.members[@status[:enemy][@subject.index][:id]].hp)
      @status[:enemy][@subject.index].store(:target, target_id)
      @status[:enemy][@subject.index].store(:damage, hp_damage)
      @status[:enemy][@subject.index].store(:critical, [critical[0], total_ctl + critical[1]])
    end
  end

  alias set_end turn_end
  def turn_end
    for i in 0...$game_party.members.size do
      @status[:actor][i].store(:hp, $game_actors[@status[:actor][i][:id]].hp)
    end

    for i in 0...$game_troop.members.size do
      @status[:enemy][i].store(:hp, $game_actors[@status[:enemy][i][:id]].hp)
    end

    skill = Skills_to_awakening.new(@status)
    for i in 0...skill.logs.length do
      @log_window.add_text(skill.logs[i])
      if i != skill.logs.length
        for time in 0...User::WAIT do
          @log_window.wait
        end
      end
    end

    set_end
  end
end


class Skills_to_awakening

  attr_accessor :logs

  def initialize(status)
    @status = status
    @logs = []
    is_awakening?
  end

  def is_awakening?
    for i in 0...$game_party.members.size do
      is_get = []

      for param in $data_actors[@status[:actor][i][:id]].note.scan(/\<#{User::MASTER_WORD}\:(.*?)\>/) do
        if param[0].match(/#{User::W1_HP}\:(\d+)([%]?)/)
          is_get.push(hp_select(i, $1, $2))
        elsif param[0].match(/#{User::W2_ATK}\:(\d+)([倍]?)/)
          is_get.push(damage_attack(i, $1, $2))
        elsif param[0].match(/#{User::W3_MAT}\:(\d+)([倍]?)/)
          is_get.push(damage_magic(i, $1, $2))
        elsif param[0].match(/#{User::W4_CTL}\:(\d+)/)
          is_get.push(critical(i, $1, $2))
        elsif param[0].match(/#{User::W5_MP}\:(\d+)([%]?)/)
          is_get.push(mp_select(i, $1, $2))
        end
      end
      skill_to(get?(@status[:actor][i][:id], is_get), i)
    end
  end

  def hp_select(i, set, opt)
    if opt == "%"
      set = "0." + set
      hp = @status[:actor][i][:max_hp] * set.to_f
    else
      hp = @status[:actor][i][:max_hp] - set.to_i
    end

    data = @status[:actor][i][:hp] - hp
    if 0 > data
      return true
    end
    return false
  end

  def damage_attack(i, set, opt)
    if opt == "倍"
      attackP = @status[:actor][i][:attack] * set.to_i
    else
      attackP = @status[:actor][i][:attack] + set.to_i
    end

    attackP += rand(2) == 0 ? rand(attackP / 10) : -rand(attackP / 10)
    if attackP < @status[:actor][i][:damage]
      return true
    end
    return false
  end

  def damage_magic(i, set, opt)
    if opt == "倍"
      magicP = @status[:actor][i][:magic] * set.to_i
    else
      magicP = @status[:actor][i][:magic] + set.to_i
    end

    magicP += rand(2) == 0 ? rand(magicP / 10) : -rand(magicP / 10)
    if magicP < @status[:actor][i][:damage]
      return true
    end
    return false
  end

  def critical(i, set, opt)
    if @status[:actor][i][:critical][0] == true
      return true
    end
    return false
  end

  def mp_select(i, set, opt)
    if opt == "%"
      set = "0." + set
      mp = @status[:actor][i][:max_mp] * set.to_f
    else
      mp = @status[:actor][i][:max_mp] - set.to_i
    end

    data = @status[:actor][i][:mp] - mp
    if 0 > data
      return true
    end
    return false
  end

  def get?(id, result)
    get = false
    result.each{|d|
      unless d
        get = false
        break
      end
      get = true
    }

    for i in 0...Skill_set::SET.length do
      if id == Skill_set::SET[i][0]
        skill = Skill_set::SET[i][1]
        option = Skill_set::SET[i][2]
        break
      end
    end

    if option && option.class == "Hash"
      if option.key?(:state)
        for i in option[:state].length do
          option = false if $game_actors[id].state?(option[:state][i])
        end
      end

      if option.key?(:skill)
        for i in option[:skill].length do
          option = false if $game_actors[id].skill_learn?(option[:skill][i])
        end
      end

      if (option != false)
        option = true
      end
    else
      option = nil
    end

    if get == true && (option == true || option == nil)
      return [true, skill]
    else
      return [false, skill]
    end
  end

  def skill_to(result, i)
    id = @status[:actor][i][:id]
    use = @status[:actor][i][:use]
    log = @status[:actor][i][:log]
    get = @status[:actor][i][:get?]

    if result[0] == true && use > 0
      if get == false
        @status[:actor][i].store(:get?, true)
        name = $game_actors[id].name
        log.sub!(/@name/, name)
        @logs.push(log)
      end
      $game_actors[id].learn_skill(result[1])
    else
      $game_actors[id].forget_skill(result[1])
    end
  end
end
