register_ai "smart_evasive_ai"
{

	OnCreate = function( self )
		aitk.basic_init( self, true, true )
	end,

	OnAttacked = aitk.basic_on_attacked, 
	states = {
		idle   = aitk.basic_smart_idle,
		pursue = aitk.basic_pursue,
		hunt   = aitk.evade_hunt,
	}
}

register_ai "smart_hybrid_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, true, true )
	end,

	OnAttacked = aitk.basic_on_attacked, 
	states = {
		idle   = aitk.basic_smart_idle,
		pursue = aitk.basic_pursue,
		hunt   = aitk.pursue_hunt,
	}
}

register_ai "charger_ai"
{
	OnCreate = function( self )
		aitk.charge_init( self, 30 )
	end,
	OnAttacked = aitk.charge_on_attacked,
	states = {
		idle        = aitk.charge_idle,
		hunt        = aitk.charge_idle,
		pursue      = aitk.basic_pursue,
		charge      = aitk.charge_charge,
		post_charge = aitk.charge_post_charge,
	}
}

register_ai "flock_ai"
{

	OnCreate = function( self )
		aitk.flock_init( self, 1, 4 )
	end,

	OnAttacked = aitk.flock_on_attacked,
	states = {
		idle = aitk.flock_idle,
		hunt = aitk.flock_hunt,
	}
}

register_ai "melee_ranged_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, false, false )
	end,

	OnAttacked = aitk.basic_on_attacked,
	states = {
		idle   = aitk.basic_smart_idle,
		pursue = aitk.basic_pursue,
		hunt   = aitk.pursue_hunt,
	}
}

register_ai "ranged_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, false, false )
	end,

	OnAttacked = aitk.basic_on_attacked,
	states = {
		idle   = aitk.basic_smart_idle,
		pursue = aitk.basic_pursue,
		hunt   = aitk.ranged_hunt,
	}
}

register_ai "sequential_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, false, false )
		self:add_property( "sequential", {3,5,3} )
		self:add_property( "sequence", 0 )
	end,

	OnAttacked = aitk.basic_on_attacked,
	states = {
		idle   = aitk.basic_smart_idle,
		pursue = aitk.basic_pursue,
		hunt   = aitk.ranged_hunt,
	}
}

register_ai "archvile_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, false, false )
		self:add_property( "attack_to", false )
		self:add_property( "on_fire", "on_fire" )
	end,

	OnAttacked = aitk.basic_on_attacked,
	states = {
		idle   = function ( self )
			if math.random(4) == 1 then
				self:ressurect(6)
				self.scount = self.scount - 1000
				return "idle"
			end
			return aitk.basic_smart_idle( self )
		end,
		pursue = function ( self )
			if math.random(4) == 1 then
				self:ressurect(6)
				self.scount = self.scount - 1000
				return "pursue"
			end
			return aitk.basic_pursue( self )
		end,
		hunt   = function( self )
			if math.random(4) == 1 then
				self:ressurect(6)
				self.scount = self.scount - 1000
				return "hunt"
			end
			local action, dist, target = aitk.try_hunt( self )
			if action then return action end
		
			local target = target.position
			if dist < 4  then
				local pos = self.position
				target = pos + (pos - target)
				area.FULL:clamp_coord( target )
			end
			if self.move_to == target then
				if aitk.move_path( self ) then
					return "hunt"
				end
			end
			self.move_to = target
			if not self:path_find( self.move_to, 10, 40 ) or ( not aitk.move_path( self ) ) then
				self.move_to = false
				self.scount  = self.scount - 1000
			end
			return "hunt"
		end,
		on_fire = function( self )
			local target = uids.get( self.target )
			if not target then return "idle" end
			self.attack_to = target.position
			self:msg("", "The " .. self.name .. " raises his arms!" )
			self.scount = self.scount - 2500
			return "fire"
		end,
		fire = function( self )
			local target = uids.get( self.target )
			if target and self:in_sight( target ) then
				self:fire( target.position, self.eq.weapon )
			else
				self:fire( self.attack_to, self.eq.weapon )
			end
			return "hunt"
		end,
	}
}

register_ai "spawner_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, false, false )
		self:add_property( "sequential", {3,5,3} )
		self:add_property( "sequence", 0 )
		self:add_property( "spawnchance", 25 )
		self:add_property( "spawnlist", false )
	end,

	OnAttacked = function( self, target )
		self.boredom = 0
	end,

	states = {
		idle   = aitk.basic_idle,
		pursue = function( self )
			if ais[ self.ai_type ].states.try_spawn( self ) then 
				return "pursue"
			end
			return aitk.basic_pursue( self )
		end,
		hunt   = function( self )
			if ais[ self.ai_type ].states.try_spawn( self ) then 
				return "hunt"
			end
			local target = player.position
			local dist   = self:distance_to( player )
			if dist < 4  then
				local pos = self.position
				target = pos + (pos - target)
				area.FULL:clamp_coord( target )
			end
			if self:direct_seek( target ) ~= MOVEOK then
				self.scount  = self.scount - 1000
			end
			return "hunt"
		end,
		try_spawn = function( self )
			if self.spawnlist and self.boredom < 4 and math.random(100) <= self.spawnchance then
				local list = self.spawnlist
				if not list.name then
					list = list[ math.random(#list) ]
				end
				local whom = list.name
				local num  = list.count
				for c=1,num do
					self:spawn(whom)
				end
				local spawnname = "a "..beings[whom].name
				if num > 1 then
					spawnname = beings[whom].name_plural
				end
				self:msg("", "The "..self.name.." spawns "..spawnname.."!")
				self.scount  = self.scount - 1000
				self.boredom = self.boredom + 1
				return true
			end
			return false
		end,
	}
}

-- BOSS AIs -------------------------------------------------------------

register_ai "angel_ai"
{

	OnCreate = function( self )
		self:add_property( "ai_state", "wait" )
		self:add_property( "move_to", false )
	end,

	OnAttacked = function( self )
		self.flags[BF_HUNTING] = true
	end,

	states = {
		wait = function( self )
			if self:in_sight( player ) or self.flags[BF_HUNTING] then return "hunt" end
			self.scount = self.scount - 1000
			return "wait"
		end,
		hunt = function( self )
			local target  = player
			local dist    = self:distance_to( target )
			local visible = self:in_sight( target )

			if math.random(30) == 1 then
				self:play_sound( "act" )
			end

			if dist == 1 then
				self:attack( player )
				return "hunt"
			end

			if self.move_to == target.position then
				if aitk.move_path( self ) then
					return "hunt"
				end
			end
			self.move_to = target.position
			if not self:path_find( self.move_to, 20, 50 ) or ( not aitk.move_path( self ) ) then
				self.move_to = false
				if not aitk.flock_seek( self, target.position ) then
					self.scount = self.scount - 1000
				end
			end
			return "hunt"
		end,
	}
}

register_ai "cyberdemon_ai"
{
	OnCreate = function( self )
		aitk.basic_init( self, true, true )
		self:add_property( "sneakshot", true )
		self:add_property( "ammo_regen", 0 )
		self:add_property( "timer", 0 )
	end,

	OnAttacked = function( self ) 
		aitk.basic_on_attacked( self )
		self.retaliate = true
	end,

	states = {
		idle   = function( self ) 
			if level.flags[ LF_BOSS ] then
				self.timer = self.timer + 1
				if self.timer % 20 == 0 then self:play_sound( "act" ) end
				if self.timer > 20 then
					self.flags[ BF_HUNTING ] = true
					self.target  = player.uid
					self.move_to = player.position
					self:path_find( self.move_to, 40, 100 )
					return "pursue"
				end
			end
			ais[ self.ai_type ].states.tick( self )
			return aitk.basic_smart_idle( self )
		end,
		pursue = function( self ) 
			ais[ self.ai_type ].states.tick( self )
			return aitk.basic_pursue( self ) 
		end,
		hunt   = function( self ) 
			ais[ self.ai_type ].states.tick( self )
			return aitk.pursue_hunt( self )
		end,
		tick   = function( self )
			if not self.inv[ "rocket" ] then
				self.ammo_regen = self.ammo_regen + 1
				if self.ammo_regen > 7 then
					self.ammo_regen = 0
					self.inv:add("rocket")
					self.inv:add("rocket")
				end
			end
		end,
	}

}

register_ai "jc_ai"
{

	OnCreate = function( self )
		aitk.basic_init( self, false, false )
		self:add_property( "attacked", false )
		self:add_property( "master", true )
		self.ai_state = "wait"
	end,

	OnAttacked = function( self )
		self.attacked = true
		if self.ai_state == "wait" then
			if not self:in_sight( player ) then
				local surround = area.around(player.position,7):clamped( area.FULL_SHRINKED )
				level:summon{ "baron", 6, area = surround }
				ui.msg("A voice bellows: \"Don't think you can surprise me!\"")
			end
			self.ai_state = "hunt"
		end
	end,

	states = {
		wait = aitk.wait,
		hunt = function( self )
			self.target = player.uid
			local target  = player
			local dist    = self:distance_to( target )
			local visible = self:in_sight( target )
			local action, has_ammo = aitk.inventory_check( self, dist > 1 )
			if action then return "hunt" end
		
			if self.attacked and math.random(3) == 1 then
				self.attacked = false
				local tp  = area.around( self.position, 10 ):clamped( area.FULL_SHRINKED ):random_coord()
				local mob = level:get_being( tp )
				if mob then
					if mob:is_player() or mob == self then
						return "hunt"
					else
						mob:kill()
					end
				end
				self:play_sound("phasing")
				level:explosion( self.position, 2, 50, 0, 0, LIGHTBLUE )
				self:relocate( tp )
				level:explosion( self.position, 4, 50, 0, 0, LIGHTBLUE )
				self.scount = self.scount - 1000
				return "hunt"
			end
	
			if (not has_ammo) or (visible and math.random(4) == 1) or (not visible and math.random(8) == 1) then
				local idx = math.max( math.min( 5 - math.floor((self.hp / self.hpmax) * 5), 5 ), 1 )
				if self.hp > self.hpmax then idx = 6 end
				local whom = { "lostsoul", "cacodemon", "knight", "baron", "revenant" , "mancubus" }
				for c=1,8 do self:spawn( whom[idx] ) end
				if self:is_visible() then
					self:msg("","Carmack raises his hands and summons hellspawn!")
				end
				self.scount = self.scount - 2000
				return "hunt"
			end

			if has_ammo then
				local shoot = true
				if not self.attacked then
					if visible then
						shoot = math.random(100) <= self.attackchance
					else
						shoot = math.random(100) <= math.floor(self.attackchance / 2)
					end
				end	
				if dist < 3 then shoot = true end			
				if shoot then
					self:fire( player, self.eq.weapon )
					return "hunt"
				end
			end

			if dist > 3 then
                if self:path_find( target.position, 10, 40 ) or ( not aitk.move_path( self ) ) then
					return "hunt"
				end
			end

			local mt = area.around( self.position, 3 ):clamped( area.FULL ):random_coord()
			if self:distance_to( mt ) > 0 then
				if self:direct_seek( mt ) == MOVEOK then
					return "hunt"
				end
			end
			self.scount = self.scount - 1000
			return "hunt"
		end,
	}
}

register_ai "teleboss_ai"
{

	OnCreate = function( self )
		self:add_property( "ai_state", "thinking" )
		self:add_property( "assigned", false )
		self:add_property( "boredom", 0 )
		self:add_property( "move_to", coord.new(0,0) )
		self:add_property( "attackchance", math.min( self.__proto.attackchance * diff[DIFFICULTY].speed, 90 ) )
	end,

	OnAttacked = function( self )
		self.boredom = 0
		self.assigned = false
	end,

	states = {
		thinking = function( self )
			local dist    = self:distance_to( player )
			local visible = self:in_sight( player )
			local no_melee = false

			if (self:has_property("telechance") and math.random(self.telechance) == 1) or (not self:has_property("telechance") and math.random(10) == 1) then
				self.assigned = false
				self.ai_state = "teleport"
				no_melee = true
			else
				self.ai_state = "hunt"
			end
			if visible and not no_melee then
				if dist == 1 then
					self:attack( player )
					return "thinking"
				elseif math.random(100) <= self.attackchance then
					self:fire( player, self.eq.weapon )
					return "thinking"
				end
			end
			no_melee = false

			if not self.assigned then
				local p = player.position
				local s = self.position
				if self.ai_state == "hunt" then
					self:path_find( p, 10, 40 )
					self.move_to = p
					self.assigned = true
				elseif self.ai_state == "teleport" then
					local phase = nil
					local phase_check = 0
					local phase_rad = self.teleradius or 5

					if dist <= phase_rad then
						local flee = coord.new(2*(s.x-p.x), 2*(s.y-p.y))
						phase = table.random_pick{ p + flee, p - flee }
						area.FULL_SHRINKED:clamp_coord( phase )
						phase = generator.drop_coord( phase, {EF_NOBEINGS,EF_NOBLOCK} )
					end

					if not phase then
						local parea = area.around( p, phase_rad ):clamped( area.FULL_SHRINKED )
						repeat
							phase = generator.random_empty_coord( { EF_NOBEINGS, EF_NOBLOCK }, parea )
							phase_check = phase_check + 1
						until ( phase and level:eye_contact( p, phase ) ) or phase_check == 25
					end
					if phase_check == 25 then
						return "thinking"
					end
					self.move_to = phase
					self.assigned = true
				end
			end
			return(self.ai_state)
		end,

		hunt = function( self )
			if math.random(30) == 1 then
				self:play_sound( "act" )
			end

			if self:distance_to( self.move_to ) == 0 then
				self.assigned = false
			else
				local move_check,move_coord = self:path_next()
				if move_check ~= MOVEOK then
					if move_check == MOVEDOOR then
--						being:open( move_coord )
					else
						self.assigned = false
						self.scount = self.scount - 200
					end
				end
			end
			self.boredom = self.boredom + 1
			if self.boredom >= 3 then
				self.assigned = false
			end
			return "thinking"
		end,

		teleport = function( self )
			self.assigned = false
			self:play_sound("phasing")
			level:explosion( self, 2, 50, 0, 0, YELLOW )
			local target = generator.drop_coord( self.move_to, {EF_NOBEINGS,EF_NOBLOCK} )
			self:relocate( target )
			level:explosion( self, 1, 50, 0, 0, YELLOW )
			self.scount = self.scount - 1000
			return "thinking"
		end,
	}
}

register_ai "mastermind_ai"
{

	OnCreate = function( self )
		self:add_property( "ai_state", "thinking" )
		self:add_property( "assigned", false )
		self:add_property( "move_to", coord.new(0,0) )
		self:add_property( "attackchance", math.min( self.__proto.attackchance * diff[DIFFICULTY].speed, 90 ) )
		self:add_property( "stun_time", 0 )
		self:add_property( "previous_hp", self.hpmax )
	end,

	OnAttacked = function( self )
		local damage_taken = self.previous_hp - self.hp
		if damage_taken >= 20 then
			self.stun_time = math.floor(damage_taken/20)
			self.assigned = false
			self:msg("", "The ".. self.name .." flinched!")
		end
	end,

	states = {
		thinking = function( self )
			local dist       = self:distance_to( player )
			local visible    = self:in_sight( player )
			self.previous_hp = self.hp

			if visible and self.stun_time == 0 then
				if dist == 1 then
					if math.random(100) <= self.attackchance then
						self:fire( player, self.eq.weapon )
					else
						self:attack( player )
					end
					return "thinking"
				elseif dist < 4 then
					self:fire( player, self.eq.weapon )
					return "thinking"
				else
					self.ai_state = "attack_spray"
				end
			else
				if self.stun_time > 0 then
					self.ai_state = "stagger"
				else
					self.ai_state = "pursue"
				end
			end


			if not self.assigned then
				local walk
				local moves = {}
				if self.ai_state == "pursue" then
					if dist > self.vision then
						self.move_to = player.position
						self:path_find( self.move_to, 40, 200 )
						self.assigned = true
					else
						for c in self.position:around_coords() do
							if player:distance_to(c) == dist and generator.is_empty(c, { EF_NOBEINGS, EF_NOBLOCK } ) then
								table.insert(moves,c:clone())
							end
						end
						if #moves > 0 then
							self.move_to = table.random_pick(moves)
							self:path_find( self.move_to, 1, 1 ) --resets normal pathfind
						else
							self.move_to = generator.random_empty_coord({ EF_NOBEINGS, EF_NOBLOCK }, area.around( self.position ))
							self:path_find( self.move_to, 1, 1 ) --hopefully these settings don't make it expensive
						end
					end
				elseif self.ai_state == "stagger" then
					self.move_to = generator.random_empty_coord( { EF_NOBEINGS, EF_NOBLOCK }, area.around( self.position ) )
				end
			end

			return self.ai_state
		end,

		attack_spray = function( self )
			local dist = self:distance_to( player )
			local spray = area.around( player.position, math.floor(dist/3) )
			local num_fire = self.eq.weapon.shots
			self.eq.weapon.shots = 1
			for shot = 1,num_fire do
				local energy = self.scount
				if math.random(2) == 1 then
					self:fire( player, self.eq.weapon )
				else
					local hit = spray:random_coord()
					area.FULL:clamp_coord(hit)
					self:fire( hit, self.eq.weapon )
				end
				if shot ~= 1 then
					self.scount = energy
				end
				--ui.delay(missiles["mnat_mastermind"].delay * 2)
			end
			self.eq.weapon.shots = num_fire
			return "thinking"
		end,

		stagger = function( self )
			self:direct_seek( self.move_to )
			self.stun_time = self.stun_time - 1
			return "thinking"
		end,

		pursue = function( self )
			if self:distance_to( self.move_to ) == 0 then
				self.assigned = false
				return "thinking"
			end
			if math.random(30) == 1 then
				self:play_sound( "act" )
			end
			local move_check, move_coord
			move_check,move_coord = self:path_next()

			-- hack to prevent crash, think of something better later
			if not move_check then
				self.scount = self.scount - 100
			end

			if not move_check or self:distance_to( player ) <= self.vision then
				self.assigned = false
			end
			return "thinking"
		end,
	}
}
