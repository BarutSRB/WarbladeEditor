// Print the disassembly listing of the function containing each supplied
// virtual address (entry, mnemonics, operands, one instruction per line).
// @category Warblade

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

public class ListingDump extends GhidraScript {
	@Override
	public void run() throws Exception {
		for (String argument : getScriptArgs()) {
			Address address = toAddr(argument);
			Function function = getFunctionContaining(address);
			if (function == null) {
				println("NO_FUNCTION " + argument);
				continue;
			}
			println("=== LISTING " + function.getName() + " " + function.getEntryPoint() + " ===");
			InstructionIterator instructions =
				currentProgram.getListing().getInstructions(function.getBody(), true);
			while (instructions.hasNext()) {
				Instruction instruction = instructions.next();
				println(instruction.getAddress() + "  " + instruction.toString());
			}
		}
	}
}
