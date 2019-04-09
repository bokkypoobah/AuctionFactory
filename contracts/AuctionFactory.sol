pragma solidity ^0.5.7;

// ----------------------------------------------------------------------------
// BokkyPooBah's Auction Factory v0.10
//
// A factory to conveniently deploy your own auction contract
//
// Factory deployment address: 0x{something}
//
// https://github.com/bokkypoobah/AuctionFactory
//
// Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2019. The MIT Licence.
// ----------------------------------------------------------------------------


// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
}


// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
// ----------------------------------------------------------------------------
contract ERC20Interface {
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

    function totalSupply() public view returns (uint);
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);
}


// ----------------------------------------------------------------------------
// Owned contract, with token recovery
// ----------------------------------------------------------------------------
contract Owned {
    bool initialised;
    address payable public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function init(address _owner) internal {
        require(!initialised);
        owner = address(uint160(_owner));
        initialised = true;
    }
    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = address(uint160(newOwner));
        newOwner = address(0);
    }
    function recoverTokens(address token, uint tokens) public onlyOwner {
        if (token == address(0)) {
            owner.transfer((tokens == 0 ? address(this).balance : tokens));
        } else {
            ERC20Interface(token).transfer(owner, tokens == 0 ? ERC20Interface(token).balanceOf(address(this)) : tokens);
        }
    }
}

contract Auction is Owned {
    using SafeMath for uint;

    uint public startDate;
    uint public endDate;
    uint public reserve;

    function init(address auctionOwner, uint _startDate, uint _endDate, uint _reserve) public {
        super.init(auctionOwner);
        startDate = _startDate;
        endDate = _endDate;
        reserve = _reserve;
    }

}


contract AuctionFactory is Owned {

    address public newAddress;
    uint public minimumFee = 0.1 ether;
    mapping(address => bool) public isChild;
    address[] public children;

    event FactoryDeprecated(address _newAddress);
    event MinimumFeeUpdated(uint oldFee, uint newFee);
    event AuctionDeployed(address indexed owner, address indexed auction, uint startDate, uint endDate, uint reserve, address uiFeeAccount, uint ownerFee, uint uiFee);

    constructor () public {
        super.init(msg.sender);
    }
    function numberOfChildren() public view returns (uint) {
        return children.length;
    }
    function deprecateFactory(address _newAddress) public onlyOwner {
        require(newAddress == address(0));
        emit FactoryDeprecated(_newAddress);
        newAddress = _newAddress;
    }
    function setMinimumFee(uint _minimumFee) public onlyOwner {
        emit MinimumFeeUpdated(minimumFee, _minimumFee);
        minimumFee = _minimumFee;
    }

    function deployAuctionContract(
        uint startDate,
        uint endDate,
        uint reserve,
        address payable uiFeeAccount
    ) public payable returns (
        Auction auction
    ) {
        require(msg.value >= minimumFee);
        require(startDate >= now);
        require(endDate > startDate);
        auction = new Auction();
        auction.init(msg.sender, startDate, endDate, reserve);
        isChild[address(auction)] = true;
        children.push(address(auction));
        uint uiFee;
        uint ownerFee;
        if (uiFeeAccount == address(0) || uiFeeAccount == owner) {
            uiFee = 0;
            ownerFee = msg.value;
        } else {
            uiFee = msg.value / 2;
            ownerFee = msg.value - uiFee;
        }
        if (uiFee > 0) {
            uiFeeAccount.transfer(uiFee);
        }
        if (ownerFee > 0) {
            owner.transfer(ownerFee);
        }
        emit AuctionDeployed(owner, address(auction), startDate, endDate, reserve, uiFeeAccount, ownerFee, uiFee);
   }
    function () external payable {
        revert();
    }
}
