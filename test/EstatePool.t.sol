// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "forge-std/Test.sol";
// import "../src/EstatePool.sol";

// contract EstatePoolTest is Test {
//     EstatePool public estatePool;
//     address public owner;
//     address public buyer;
//     address public auctionParticipant;

//     // Events to test
//     event TokenListed(address indexed owner, string indexed name, uint256 indexed id);
//     event TokenBought(address indexed from, address indexed to, uint256 indexed tokenid);
//     event AuctionCreated(uint256 indexed auctionId, address indexed creator, uint256 indexed tokenId, uint256 amount);
//     event TokenDelisted(uint256 indexed tokenId);
//     event AuctionPaid(address indexed payer, address indexed owner, uint256 indexed auctionId, uint256 amount);

//     function setUp() public {
//         // Initialize with IPFS URI
//         estatePool = new EstatePool("ipfs://QmExample/{id}");
//         owner = address(1);
//         buyer = address(2);
//         auctionParticipant = address(3);

//         // Fund test addresses
//         vm.deal(owner, 100 ether);
//         vm.deal(buyer, 100 ether);
//         vm.deal(auctionParticipant, 100 ether);
//     }

//     function testCreateAsset() public {
//         vm.startPrank(owner);

//         vm.expectEmit(true, true, true, true);
//         emit TokenListed(owner, "Test Estate", 1);

//         EstatePool.TokenData memory tokenData = estatePool.CreateAsset(
//             "Test Estate",
//             100, // totalPlots
//             50, // amtToSell
//             EstatePool.EstateType.Land
//         );

//         assertEq(tokenData.Name, "Test Estate");
//         assertEq(tokenData.Owner, owner);
//         assertEq(tokenData.TotalPlots, 100);
//         assertEq(tokenData.AmountToBeSold, 50);
//         assertEq(uint256(tokenData.Type), uint256(EstatePool.EstateType.Land));

//         assertEq(estatePool.GetTokenCounter(), 1);
//         assertEq(estatePool.GetAvailableTokenAmount(1), 50);

//         vm.stopPrank();
//     }

//     function testBuyPlot() public {
//         // First create an asset
//         vm.startPrank(owner);
//         EstatePool.TokenData memory tokenData = estatePool.CreateAsset(
//             "Test Estate",
//             100, // totalPlots
//             50, // amtToSell
//             EstatePool.EstateType.Land
//         );
//         vm.stopPrank();

//         // Now test buying
//         vm.startPrank(buyer);
//         uint256 purchaseAmount = 10;
//         uint256 paymentAmount = 1 ether;

//         vm.expectEmit(true, true, true, true);
//         emit TokenBought(owner, buyer, 1);

//         (uint256 tokenId, uint256 amountBought) = estatePool.BuyPlot{value: paymentAmount}(
//             1, // tokenId
//             purchaseAmount,
//             paymentAmount
//         );

//         assertEq(tokenId, 1);
//         assertEq(amountBought, purchaseAmount);
//         assertEq(estatePool.GetAvailableTokenAmount(1), 40); // 50 - 10

//         // Check token balance
//         assertEq(estatePool.balanceOf(buyer, 1), purchaseAmount);

//         vm.stopPrank();
//     }

//     function testAuctionAsset() public {
//         // First create an asset
//         vm.startPrank(owner);
//         estatePool.CreateAsset("Auction Estate", 100, 50, EstatePool.EstateType.Commercial);

//         // Approve contract for auction
//         uint256 auctionAmount = 20;

//         vm.expectEmit(true, true, true, true);
//         emit AuctionCreated(1, owner, 1, auctionAmount);

//         (bool success, uint256 auctionId) = estatePool.AuctionAsset(1, auctionAmount);

//         assertTrue(success);
//         assertEq(auctionId, 1);

//         // Verify auction data
//         EstatePool.AuctionData[] memory auctions = estatePool.GetAuctions();
//         assertEq(auctions.length, 1);
//         assertEq(auctions[0].TokenId, 1);
//         assertEq(auctions[0].AmountToSell, auctionAmount);
//         assertEq(auctions[0].Owner, owner);
//         assertFalse(auctions[0].completed);

//         vm.stopPrank();
//     }

//     function testPayBid() public {
//         // Setup: Create asset and auction it
//         vm.startPrank(owner);
//         estatePool.CreateAsset("Auction Estate", 100, 50, EstatePool.EstateType.Commercial);
//         uint256 auctionAmount = 20;
//         (bool success, uint256 auctionId) = estatePool.AuctionAsset(1, auctionAmount);
//         vm.stopPrank();

//         // Test bid payment
//         vm.startPrank(auctionParticipant);
//         uint256 bidAmount = 2 ether;

//         vm.expectEmit(true, true, true, true);
//         emit AuctionPaid(auctionParticipant, owner, auctionId, bidAmount);

//         bool bidSuccess = estatePool.PayBid{value: bidAmount}(auctionId, bidAmount);

//         assertTrue(bidSuccess);

//         // Verify auction completion
//         EstatePool.AuctionData memory auctionData = estatePool.auction(auctionId);
//         assertTrue(auctionData.completed);

//         // Check token transfer
//         assertEq(estatePool.balanceOf(auctionParticipant, 1), auctionAmount);

//         vm.stopPrank();
//     }

//     function testFailBuyPlotInsufficientPayment() public {
//         vm.startPrank(owner);
//         estatePool.CreateAsset("Test Estate", 100, 50, EstatePool.EstateType.Land);
//         vm.stopPrank();

//         vm.startPrank(buyer);
//         uint256 purchaseAmount = 10;
//         uint256 paymentAmount = 0.1 ether;
//         uint256 expectedPayment = 1 ether;

//         vm.expectRevert("The amount sent is not enough for purchase");
//         estatePool.BuyPlot{value: paymentAmount}(1, purchaseAmount, expectedPayment);
//         vm.stopPrank();
//     }

//     function testFailBuyPlotExceedAvailable() public {
//         vm.startPrank(owner);
//         estatePool.CreateAsset("Test Estate", 100, 50, EstatePool.EstateType.Land);
//         vm.stopPrank();

//         vm.startPrank(buyer);
//         uint256 purchaseAmount = 51; // More than available
//         uint256 paymentAmount = 1 ether;

//         vm.expectRevert("Purchase amount exceeds the availiable amount");
//         estatePool.BuyPlot{value: paymentAmount}(1, purchaseAmount, paymentAmount);
//         vm.stopPrank();
//     }

//     function testGetUserTokensData() public {
//         // Create asset
//         vm.startPrank(owner);
//         estatePool.CreateAsset("Test Estate", 100, 50, EstatePool.EstateType.Land);
//         vm.stopPrank();

//         // Buy some tokens
//         vm.startPrank(buyer);
//         uint256 purchaseAmount = 10;
//         estatePool.BuyPlot{value: 1 ether}(1, purchaseAmount, 1 ether);

//         // Get user tokens data
//         EstatePool.UserTokenData[] memory userTokens = estatePool.GetUserTokensData(buyer);

//         assertEq(userTokens.length, 1);
//         assertEq(userTokens[0].tokenId, 1);
//         assertEq(userTokens[0].amountOwned, purchaseAmount);

//         vm.stopPrank();
//     }
// }
