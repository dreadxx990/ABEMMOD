import hooks;
import statuses;
from statuses import StatusHook;
import artifacts;
from bonus_effects import BonusEffect;
import listed_values;
import region_effects;
#section server
import empire;
import components.Abilities;
#section all

class DisableShields : StatusHook {
	Document doc("Disables the shields of the ship affected by this status.");
	Argument preserve("Preserve Power", AT_Boolean, "False", doc="Whether the ship's shields should be set to their previous strength once the status is disabled.");
	
#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null) {
			ship.Shield = 0;
			ship.MaxShield = 0;
		}
	}
	
	void onDestroy(Object& obj, Status@ status, any@ data) override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.MaxShield = ship.blueprint.getEfficiencySum(SV_ShieldCapacity);
	}
	
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null) {
			ship.Shield = 0;
			ship.MaxShield = 0;
		}
		return true;
	}
#section all
}

class DisableStatus : StatusHook {
	Document doc("Removes a certain status from objects affected by this status.");
	Argument arg_type("Type", AT_Status, doc="Status type to remove.");
	
#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		const StatusType@ type = getStatusType(arg_type.str);
		if(type !is null) {
			obj.removeStatusType(type.id);
			data.store(@type);
		}
	}
	
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		const StatusType@ type;
		data.retrieve(@type);
		if(type !is null) {
			obj.removeStatusType(type.id);
		}
		return true;
	}
#section all
}

class DisableAbility : StatusHook {
	Document doc("Disables a certain ability type on objects affected by this status.");
	Argument arg_type("Type", AT_Ability, doc="Ability type to disable.");
	
#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		const AbilityType@ type = getAbilityType(arg_type.str);
		if(type !is null && obj.hasAbilities) {
			int id = int(type.id);
			if(cast<Abilities>(obj.get_Abilities()).getAbility(id) !is null)
				obj.disableAbility(id);
			data.store(@type);
		}
	}
	
	void onDestroy(Object& obj, Status@ status, any@ data) override {
		const AbilityType@ type;
		data.retrieve(@type);
		if(type !is null && obj.hasAbilities) {
			int id = int(type.id);
			if(cast<Abilities>(obj.get_Abilities()).getAbility(id) !is null)
				obj.enableAbility(id);
		}
	}
	
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		const AbilityType@ type;
		data.retrieve(@type);
		if(type !is null && obj.hasAbilities) {
			int id = int(type.id);
			if(cast<Abilities>(obj.get_Abilities()).getAbility(id) !is null)
				obj.disableAbility(id);
		}
		return true;
	}
}

class DealRandomDamage : StatusHook {
	Document doc("Deals damage from random directions to objects affected by this status.");
	Argument damage("Damage", AT_Decimal, "25.0", doc="Damage to deal. Defaults to 25.");
	Argument damagepct("Damage Percent", AT_Decimal, "0.001", doc="Percentage of target's maximum hull to deal. Defaults to 0.001 (0.1% of hull).");
	Argument shieldpct("Shield Percent", AT_Decimal, "0.001", doc="Percentage of target's maximum shields to drain. This drain precedes shield damage. Defaults to 0.001 (0.1% of shield).");
	Argument shieldmult("Shield Multiplier", AT_Decimal, "5", doc="How much more effective the damage is against shields. Defaults to 5.");
	Argument shieldonly("Shields Only", AT_Boolean, "False", doc="Whether the damage only affects shields.");
	
#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		Ship@ ship = cast<Ship>(obj);
		double totalHP = 0;
		if(ship !is null)
			totalHP = ship.blueprint.design.totalHP;
		else {
			Orbital@ orb = cast<Orbital>(obj);
			if(orb !is null)
				totalHP = orb.maxHealth + orb.maxArmor;
		}
		DamageEvent dmg;
		dmg.damage = (damage.decimal + damagepct.decimal * totalHP) * time;
		if(ship !is null && ship.Shield > 0) {
			double overflow = 0;
			ship.Shield = max(ship.Shield - shieldpct.decimal * ship.MaxShield, 0.0);
			overflow = dmg.damage * shieldmult.decimal - ship.Shield;
			ship.Shield -= dmg.damage * shieldmult.decimal;
			if(ship.Shield < 0)
				ship.Shield = 0;
			if(overflow > 0)
				dmg.damage = overflow / shieldmult.decimal;
			else
				dmg.damage = 0;
		}
		if(shieldonly.boolean) {
			dmg.damage = 0;
		}
		if(dmg.damage > 0) {
			dmg.partiality = time;
			dmg.impact = 0;
			@dmg.obj = null;
			@dmg.target = obj;
			obj.damage(dmg, -1.0, vec2d(randomi(-1, 1), randomi(-1, 1)));
		}
		obj.engaged = true;
		return true;
	}
#section all
}

class ShieldRegenBoost : StatusHook {
	Document doc("Boosts the shield regeneration of a ship by a percentage of its own regenerative ability.");
	Argument percentage("Percentage", AT_Decimal, "0.1", doc="Percentage boost. Defaults to 0.1 (10% of ship's regeneration).");
	
#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double regen = 0;
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			regen = ship.blueprint.getEfficiencySum(SV_ShieldRegen) * percentage.decimal;
		ship.Shield = min(ship.Shield + regen, ship.MaxShield);
		return true;
	}
#section all
}

class KillCrew : StatusHook {
	Document doc("Kills the crew of an object over time, leaving a derelict behind. Remnants simply take shield damage, if applicable.");
	Argument damage("Shield Damage", AT_Decimal, "30.0", doc="Damage dealt to shields. If -1, shields are unaffected and do not delay the effect. Defaults to 30.");
	Argument damagepct("Shield Damage Percent", AT_Decimal, "0.001", doc="Percentage of shield capacity drained in addition to Shield Damage. Defaults to 0.001 (0.1% of shield capacity).");
	Argument duration("Time", AT_Decimal, "300.0", doc="Amount of time before object becomes a derelict.");
	
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double timeLeft = duration.decimal;
		data.store(timeLeft);
	}
	
	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return emp !is defaultEmpire;
	}
	
#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double timeLeft = 0;
		data.retrieve(timeLeft);
		Ship@ ship = cast<Ship>(obj);
		timeLeft -= time;
		if(ship !is null && ship.Shield > 0) {
			ship.Shield -= max(damage.decimal, 0.0) + damagepct.decimal * ship.MaxShield;
			if(ship.Shield < 0)
				ship.Shield = 0;
			if(ship.Shield > 0 && damage.decimal != -1)
				timeLeft += time;
		}
		if(timeLeft < 0 && obj.owner !is Creeps) {
			if(obj.isShip && !obj.hasLeaderAI)
				obj.destroy();
			@obj.owner = defaultEmpire;
			if(obj.hasStatuses)
				obj.addStatus(getStatusID("DerelictShip"));
			return false;
		}
		data.store(timeLeft);
		return true;
	}
#section all
}

class StatusFreeFTLSystem : StatusHook {
	Document doc("Objects FTLing out of the system this status is active in can FTL for free. NOTE: DO NOT USE THIS IN ANYTHING EXCEPT AddRegionStatus() HOOKS CALLED DURING SYSTEM GENERATION WITHOUT CONSULTING ONE OR MORE STAR RULER 2 DEVELOPERS. AND PREFERABLY NOT EVEN THEN. IT MAY BREAK.");
	
#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.FreeFTLMask |= owner.mask;
		return true;
	}
#section all
}

class StatusBlockFTLSystem : StatusHook {
	Document doc("Objects in the system this status is active in cannot FTL at all. NOTE: DO NOT USE THIS IN ANYTHING EXCEPT AddRegionStatus() HOOKS CALLED DURING SYSTEM GENERATION WITHOUT CONSULTING OE OR MORE STAR RULER 2 DEVELOPERS. AND PREFERABLY NOT EVEN THEN. IT MAY BREAK.");
	
#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(obj.region !is null && obj.owner !is null && obj.owner.valid) {
			obj.region.BlockFTLMask |= obj.owner.mask;
		}
		return true;
	}
#section all
}