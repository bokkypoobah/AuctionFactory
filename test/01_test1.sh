#!/bin/bash
# ----------------------------------------------------------------------------------------------
# Testing the smart contract
#
# Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2019. The MIT Licence.
# ----------------------------------------------------------------------------------------------

# echo "Options: [full|takerSell|takerBuy|exchange]"

MODE=${1:-full}

source settings
echo "---------- Settings ----------" | tee $TEST1OUTPUT
cat ./settings | tee -a $TEST1OUTPUT
echo "" | tee -a $TEST1OUTPUT

CURRENTTIME=`date +%s`
CURRENTTIMES=`perl -le "print scalar localtime $CURRENTTIME"`
START_DATE=`echo "$CURRENTTIME+45" | bc`
START_DATE_S=`perl -le "print scalar localtime $START_DATE"`
END_DATE=`echo "$CURRENTTIME+60*2" | bc`
END_DATE_S=`perl -le "print scalar localtime $END_DATE"`

printf "CURRENTTIME = '$CURRENTTIME' '$CURRENTTIMES'\n" | tee -a $TEST1OUTPUT
printf "START_DATE  = '$START_DATE' '$START_DATE_S'\n" | tee -a $TEST1OUTPUT
printf "END_DATE    = '$END_DATE' '$END_DATE_S'\n" | tee -a $TEST1OUTPUT

# Make copy of SOL file ---
# rsync -rp $SOURCEDIR/* . --exclude=Multisig.sol --exclude=test/
rsync -rp $SOURCEDIR/* . --exclude=Multisig.sol
# Copy modified contracts if any files exist
find ./modifiedContracts -type f -name \* -exec cp {} . \;

# --- Modify parameters ---
#`perl -pi -e "s/emit LogUint.*$//" $EXCHANGESOL`
# Does not work `perl -pi -e "print if(!/emit LogUint/);" $EXCHANGESOL`

DIFFS1=`diff -r -x '*.js' -x '*.json' -x '*.txt' -x 'testchain' -x '*.md' -x '*.sh' -x 'settings' -x 'modifiedContracts' $SOURCEDIR .`
echo "--- Differences $SOURCEDIR/*.sol *.sol ---" | tee -a $TEST1OUTPUT
echo "$DIFFS1" | tee -a $TEST1OUTPUT

solc_0.5.7 --version | tee -a $TEST1OUTPUT

echo "var factoryOutput=`solc_0.5.7 --allow-paths . --optimize --pretty-json --combined-json abi,bin,interface $FACTORYSOL`;" > $FACTORYJS
echo "var tokenOutput=`solc_0.5.7 --allow-paths . --optimize --pretty-json --combined-json abi,bin,interface $TOKENSOL`;" > $TOKENJS
# ../scripts/solidityFlattener.pl --contractsdir=../contracts --mainsol=$TOKENFACTORYSOL --outputsol=$TOKENFACTORYFLATTENED --verbose | tee -a $TEST1OUTPUT


if [ "$MODE" = "compile" ]; then
  echo "Compiling only"
  exit 1;
fi

geth --verbosity 3 attach $GETHATTACHPOINT << EOF | tee -a $TEST1OUTPUT
loadScript("$FACTORYJS");
loadScript("$TOKENJS");
loadScript("lookups.js");
loadScript("functions.js");

var factoryAbi = JSON.parse(factoryOutput.contracts["$FACTORYSOL:$FACTORYNAME"].abi);
var factoryBin = "0x" + factoryOutput.contracts["$FACTORYSOL:$FACTORYNAME"].bin;
var auctionAbi = JSON.parse(factoryOutput.contracts["$FACTORYSOL:$AUCTIONNAME"].abi);
var tokenAbi = JSON.parse(tokenOutput.contracts["$TOKENSOL:$TOKENNAME"].abi);
var tokenBin = "0x" + tokenOutput.contracts["$TOKENSOL:$TOKENNAME"].bin;

// console.log("DATA: factoryAbi=" + JSON.stringify(factoryAbi));
// console.log("DATA: factoryBin=" + JSON.stringify(factoryBin));
// console.log("DATA: auctionAbi=" + JSON.stringify(auctionAbi));
// console.log("DATA: tokenAbi=" + JSON.stringify(tokenAbi));
// console.log("DATA: tokenBin=" + JSON.stringify(tokenBin));


unlockAccounts("$PASSWORD");
printBalances();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var deployGroup1Message = "Deploy Group #1 - Factory & Token";
var symbol="$SYMBOL";
var name="$NAME";
var decimals="$DECIMALS";
var totalSupply=new BigNumber("$TOTALSUPPLY").shift(decimals);
// -----------------------------------------------------------------------------
console.log("RESULT: ---------- " + deployGroup1Message + " ----------");
var factoryContract = web3.eth.contract(factoryAbi);
var factoryTx = null;
var factoryAddress = null;
var factory = factoryContract.new({from: deployer, data: factoryBin, gas: 4000000, gasPrice: defaultGasPrice},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        factoryTx = contract.transactionHash;
      } else {
        factoryAddress = contract.address;
        addAccount(factoryAddress, "Factory");
        addFactoryContractAddressAndAbi(factoryAddress, factoryAbi);
        console.log("DATA: var factoryAddress=\"" + factoryAddress + "\";");
        console.log("DATA: var factoryAbi=" + JSON.stringify(factoryAbi) + ";");
        console.log("DATA: var factory=eth.contract(factoryAbi).at(factoryAddress);");
      }
    }
  }
);
var tokenContract = web3.eth.contract(tokenAbi);
var tokenTx = null;
var tokenAddress = null;
var token = tokenContract.new(symbol, name, decimals, totalSupply, {from: deployer, data: tokenBin, gas: 4000000, gasPrice: defaultGasPrice},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        tokenTx = contract.transactionHash;
      } else {
        tokenAddress = contract.address;
        addAccount(tokenAddress, "Token '" + symbol + "' '" + name + "'");
        addTokenContractAddressAndAbi(tokenAddress, tokenAbi);
        addAddressSymbol(tokenAddress, token.symbol());
        console.log("DATA: var tokenAddress=\"" + tokenAddress + "\";");
        console.log("DATA: var tokenAbi=" + JSON.stringify(tokenAbi) + ";");
        console.log("DATA: var token=eth.contract(tokenAbi).at(tokenAddress);");
      }
    }
  }
);
while (txpool.status.pending > 0) {
}
printBalances();
failIfTxStatusError(factoryTx, deployGroup1Message + " - Factory");
printTxData("factoryTx", factoryTx);
console.log("RESULT: ");
printTokenContractDetails();
console.log("RESULT: ");
printFactoryContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var deployGroup2Message = "Deploy Group #1 - Deploy Auction";
var startDate = new Date() / 1000 + 300; // 5 minutes
var endDate = new Date() / 1000 + 600; // 10 minutes
var reserve = new BigNumber("1").shift(18);
var feeInEthers = new BigNumber("1.123456789").shift(18);
// -----------------------------------------------------------------------------
console.log("RESULT: ---------- " + deployGroup2Message + " ----------");
var deployAuction_1Tx = factory.deployAuctionContract(tokenAddress, startDate, endDate, reserve, uiFeeAccount, {from: user1, value: feeInEthers, gas: 2000000, gasPrice: defaultGasPrice});
while (txpool.status.pending > 0) {
}
var auctionContract = getAuctionContractDeployed();
console.log("RESULT: auctionContract=#" + auctionContract.length + " " + JSON.stringify(auctionContract));
var auctionAddress = auctionContract[0];
var auction = web3.eth.contract(auctionAbi).at(auctionAddress);
addAccount(auctionAddress, "Auction start=" + new Date(startDate * 1000).toString() +
  ", end=" + new Date(endDate * 1000).toString() +
  ", reserve=" + auction.reserve().shift(-18));
addAuctionContractAddressAndAbi(auctionAddress, auctionAbi);
console.log("DATA: var auctionAddress=\"" + auctionAddress + "\";");
console.log("DATA: var auctionAbi=" + JSON.stringify(auctionAbi) + ";");
console.log("DATA: var auction=eth.contract(auctionAbi).at(auctionAddress);");

printBalances();
failIfTxStatusError(deployAuction_1Tx, deployGroup2Message + " - Auction");
printTxData("deployAuction_1Tx", deployAuction_1Tx);
console.log("RESULT: ");
printTokenContractDetails();
console.log("RESULT: ");
printFactoryContractDetails();
console.log("RESULT: ");
printAuctionContractDetails();
console.log("RESULT: ");


exit;

// -----------------------------------------------------------------------------
var testSecondInitMessage = "Test second init";
var symbol = "TEST2";
var name = "Test 2";
var decimals = 18;
var totalSupply = new BigNumber("1000000001").shift(decimals);
// Simulate error by commenting out in Owned:init(...) either of the two lines:
//   require(!initialised);
//   initialised = true;
// -----------------------------------------------------------------------------
console.log("RESULT: ---------- " + testSecondInitMessage + " ----------");
// function init(address tokenOwner, string memory symbol, string memory name, uint8 decimals, uint fixedSupply)
console.log("RESULT: user2: " + user2);
console.log("RESULT: symbol: " + symbol);
console.log("RESULT: name: " + name);
console.log("RESULT: decimals: " + decimals);
console.log("RESULT: totalSupply: " + totalSupply.toString());
var testSecondInit_1Tx = token.init(user2, symbol, name, decimals, totalSupply.toString(), {from: user2, value: 0, gas: 2000000, gasPrice: defaultGasPrice});
while (txpool.status.pending > 0) {
}
printBalances();
passIfTxStatusError(testSecondInit_1Tx, testSecondInitMessage + " - expecting init() to fail");
printTxData("testSecondInit_1Tx", testSecondInit_1Tx);
console.log("RESULT: ");
printTokenContractDetails();
console.log("RESULT: ");




EOF
grep "DATA: " $TEST1OUTPUT | sed "s/DATA: //" > $DEPLOYMENTDATA
cat $DEPLOYMENTDATA
grep "RESULT: " $TEST1OUTPUT | sed "s/RESULT: //" > $TEST1RESULTS
cat $TEST1RESULTS
egrep -e "tokenTx.*gasUsed|ordersTx.*gasUsed" $TEST1RESULTS
